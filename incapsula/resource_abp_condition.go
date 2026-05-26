package incapsula

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/hashicorp/terraform-plugin-sdk/v2/diag"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
)

// TODO: removed `template`
// TODO: removed `owner`
// TODO: removed `recommended_directives`

func resourceAbpCondition() *schema.Resource {
	return &schema.Resource{
		CreateContext: resourceAbpConditionCreate,
		ReadContext:   resourceAbpConditionRead,
		UpdateContext: resourceAbpConditionUpdate,
		DeleteContext: resourceAbpConditionDelete,

		Importer: &schema.ResourceImporter{
			StateContext: resourceAbpConditionImport,
		},

		Description: "Provides an ABP Condition resource. " +
			"A condition contains MOI expression evaluated against incoming requests. " +
			"Conditions are referenced from policies (directly or via condition lists) to drive directive actions.",

		Schema: map[string]*schema.Schema{
			"account_id": {
				Description: "ABP account UUID this Condition belongs to.",
				Type:        schema.TypeString,
				Required:    true,
				ForceNew:    true,
			},
			"name": {
				Description: "Human-readable name of the condition. 1..100 characters.",
				Type:        schema.TypeString,
				Required:    true,
			},
			// TODO: map missing description to an empty string
			"description": {
				Description: "Description of the condition. Required by the API; empty string is allowed.",
				Type:        schema.TypeString,
				Required:    true,
			},
			"code": {
				Description: "MOI expression evaluated against the request.",
				Type:        schema.TypeString,
				Required:    true,
			},
			"is_managed_condition": {
				// TODO: better description
				Description: "Tells if the condition is managed by Imperva",
				Type:        schema.TypeBool,
				Computed:    true,
			},
			"last_change_by": {
				Description: "Identifier of the user who last changed this condition.",
				Type:        schema.TypeString,
				Computed:    true,
			},
			"created_at": {
				Description: "RFC3339 timestamp at which the Condition was created.",
				Type:        schema.TypeString,
				Computed:    true,
			},
			"modified_at": {
				Description: "RFC3339 timestamp at which the Condition was last modified.",
				Type:        schema.TypeString,
				Computed:    true,
			},
		},
	}
}

func extractAbpCondition(data *schema.ResourceData) AbpCondition {
	condition := AbpCondition{
		Name:        data.Get("name").(string),
		Description: data.Get("description").(string),
		Code:        data.Get("code").(string),
	}
	return condition
}

func serializeAbpCondition(data *schema.ResourceData, condition *AbpCondition) error {
	if err := data.Set("name", condition.Name); err != nil {
		return err
	}
	if err := data.Set("description", condition.Description); err != nil {
		return err
	}
	if err := data.Set("code", condition.Code); err != nil {
		return err
	}
	// TODO: Remove empty string check
	if condition.AccountId != "" {
		if err := data.Set("account_id", condition.AccountId); err != nil {
			return err
		}
	}
	if err := data.Set("is_managed_condition", condition.Owner == "imperva"); err != nil {
		return err
	}
	if condition.LastChangeBy != nil {
		if err := data.Set("last_change_by", *condition.LastChangeBy); err != nil {
			return err
		}
	} else {
		if err := data.Set("last_change_by", ""); err != nil {
			return err
		}
	}
	if condition.CreatedAt != nil {
		if err := data.Set("created_at", *condition.CreatedAt); err != nil {
			return err
		}
	}
	if condition.ModifiedAt != nil {
		if err := data.Set("modified_at", *condition.ModifiedAt); err != nil {
			return err
		}
	}
	return nil
}

func resourceAbpConditionCreate(ctx context.Context, data *schema.ResourceData, m interface{}) diag.Diagnostics {
	client := m.(*Client)
	accountId := data.Get("account_id").(string)

	created, err := client.CreateAbpCondition(accountId, extractAbpCondition(data))
	if err != nil {
		return diag.FromErr(err)
	}

	data.SetId(created.Id)
	if err := serializeAbpCondition(data, created); err != nil {
		return diag.FromErr(err)
	}

	log.Printf("[INFO] Created ABP Condition %s in account %s", created.Id, accountId)
	return nil
}

func resourceAbpConditionRead(ctx context.Context, data *schema.ResourceData, m interface{}) diag.Diagnostics {
	client := m.(*Client)
	id := data.Id()
	if id == "" {
		return nil
	}

	condition, status, err := client.ReadAbpCondition(id)
	if err != nil {
		return diag.FromErr(err)
	}
	if status == 404 || condition == nil {
		log.Printf("[INFO] ABP Condition %s not found, removing from state", id)
		data.SetId("")
		return nil
	}

	if err := serializeAbpCondition(data, condition); err != nil {
		return diag.FromErr(err)
	}
	return nil
}

func resourceAbpConditionUpdate(ctx context.Context, data *schema.ResourceData, m interface{}) diag.Diagnostics {
	client := m.(*Client)
	id := data.Id()

	updated, err := client.UpdateAbpCondition(id, extractAbpCondition(data))
	if err != nil {
		return diag.FromErr(err)
	}

	if err := serializeAbpCondition(data, updated); err != nil {
		return diag.FromErr(err)
	}
	return nil
}

func resourceAbpConditionDelete(ctx context.Context, data *schema.ResourceData, m interface{}) diag.Diagnostics {
	client := m.(*Client)
	id := data.Id()

	if err := client.DeleteAbpCondition(id); err != nil {
		return diag.FromErr(err)
	}

	data.SetId("")
	return nil
}

// Supports "<condition_id>" or "<account_id>/<condition_id>". The account_id
// segment is required because reading a Condition does not return enough
// information to address sub-accounts on its own.
func resourceAbpConditionImport(ctx context.Context, data *schema.ResourceData, m interface{}) ([]*schema.ResourceData, error) {
	raw := strings.TrimSpace(data.Id())
	if raw == "" {
		return nil, fmt.Errorf("expected import ID to be '<condition_id>' or '<account_id>/<condition_id>'")
	}

	if strings.Contains(raw, "/") {
		parts := strings.SplitN(raw, "/", 2)
		if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
			return nil, fmt.Errorf("invalid import ID %q: want '<condition_id>' or '<account_id>/<condition_id>'", raw)
		}
		if err := data.Set("account_id", strings.TrimSpace(parts[0])); err != nil {
			return nil, fmt.Errorf("setting account_id: %w", err)
		}
		data.SetId(strings.TrimSpace(parts[1]))
	} else {
		data.SetId(raw)
	}

	return []*schema.ResourceData{data}, nil
}
