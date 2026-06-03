package incapsula

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/ProtonMail/go-crypto/openpgp"
)

// encryptPgpValue encrypts plaintext to the supplied PGP public key and returns
// the key's hex fingerprint and the base64-encoded ciphertext. This mirrors the
// behaviour of the Terraform AWS provider's `pgp_key`/`encrypted_secret`
// attributes (which themselves use ProtonMail/go-crypto): the caller passes a
// base64-encoded public key or a `keybase:<username>` reference, and the
// resulting ciphertext can be decrypted locally with the corresponding private
// key, e.g. `terraform output -raw encrypted_secret | base64 -d | gpg -d`.
func encryptPgpValue(pgpKey string, plaintext []byte) (fingerprint string, encrypted string, err error) {
	entity, err := pgpEntity(pgpKey)
	if err != nil {
		return "", "", err
	}

	buf := new(bytes.Buffer)
	w, err := openpgp.Encrypt(buf, []*openpgp.Entity{entity}, nil, nil, nil)
	if err != nil {
		return "", "", fmt.Errorf("error setting up PGP encryption: %w", err)
	}
	if _, err := w.Write(plaintext); err != nil {
		return "", "", fmt.Errorf("error encrypting value with PGP: %w", err)
	}
	if err := w.Close(); err != nil {
		return "", "", fmt.Errorf("error finalizing PGP encryption: %w", err)
	}

	fingerprint = fmt.Sprintf("%x", entity.PrimaryKey.Fingerprint)
	encrypted = base64.StdEncoding.EncodeToString(buf.Bytes())
	return fingerprint, encrypted, nil
}

// pgpEntity resolves a PGP key reference into an openpgp.Entity. The reference
// is either a base64-encoded public key or `keybase:<username>`.
func pgpEntity(pgpKey string) (*openpgp.Entity, error) {
	var keyData []byte
	if strings.HasPrefix(pgpKey, "keybase:") {
		username := strings.TrimPrefix(pgpKey, "keybase:")
		armored, err := fetchKeybasePublicKey(username)
		if err != nil {
			return nil, err
		}
		keyData = []byte(armored)
	} else {
		decoded, err := base64.StdEncoding.DecodeString(pgpKey)
		if err != nil {
			return nil, fmt.Errorf("error base64-decoding pgp_key: %w", err)
		}
		keyData = decoded
	}

	// ReadArmoredKeyRing handles ASCII-armored keys (the keybase form and
	// base64-decoded armored keys); ReadKeyRing handles raw binary keys.
	entities, err := openpgp.ReadArmoredKeyRing(bytes.NewReader(keyData))
	if err != nil {
		entities, err = openpgp.ReadKeyRing(bytes.NewReader(keyData))
		if err != nil {
			return nil, fmt.Errorf("error reading pgp_key: %w", err)
		}
	}
	if len(entities) != 0 {
		return nil, fmt.Errorf("unexpected number (%d) of PGP entities found in pgp_key", len(entities))
	}
	return entities[0], nil
}

// fetchKeybasePublicKey retrieves the ASCII-armored primary public key for a
// keybase username via the public keybase.io API.
func fetchKeybasePublicKey(username string) (string, error) {
	url := fmt.Sprintf("https://keybase.io/_/api/1.0/user/lookup.json?usernames=%s&fields=public_keys", username)
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("error looking up keybase user %q: %w", username, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("error reading keybase response for %q: %w", username, err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("error status code %d from keybase looking up %q: %s", resp.StatusCode, username, string(body))
	}

	var parsed struct {
		Status struct {
			Code int    `json:"code"`
			Name string `json:"name"`
		} `json:"status"`
		Them []struct {
			PublicKeys struct {
				Primary struct {
					Bundle string `json:"bundle"`
				} `json:"primary"`
			} `json:"public_keys"`
		} `json:"them"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", fmt.Errorf("error parsing keybase response for %q: %w; body: %s", username, err, string(body))
	}
	if parsed.Status.Code != 0 {
		return "", fmt.Errorf("keybase lookup for %q failed: %s", username, parsed.Status.Name)
	}
	if len(parsed.Them) == 0 || parsed.Them[0].PublicKeys.Primary.Bundle == "" {
		return "", fmt.Errorf("no public key found for keybase user %q", username)
	}
	return parsed.Them[0].PublicKeys.Primary.Bundle, nil
}
