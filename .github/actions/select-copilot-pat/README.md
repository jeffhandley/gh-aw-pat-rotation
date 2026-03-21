# Select Copilot PAT
Selects a random Copilot PAT from a numbered pool of secrets. This
addresses limitations that arise from having a single PAT shared
across all agentic workflows, such as rate-limiting.

**This is a stop-gap workaround.** As soon as organization/enterprise
billing is offered for agentic workflows, this approach will be removed
from our workflows.

## Usage
Add the following frontmatter at the top-level of an agentic workflow.
These elements are not supported through [imports][1], so they must be
copied into all workflows.

Up to 10 `SECRET_#` environment variables can be passed to the action,
numbered 0-9. Different workflows can use different pools of PATs if
desired. Change the `secrets.COPILOT_PAT_0` through `secrets.COPILOT_PAT_9`
secret names in both the `select-copilot-pat` step `env` values and in the
`case` expression under the `engine: env` configuration.

```yml
on:
  # Add the pre-activation step of selecting a random PAT from the supplied secrets
  steps:
    - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      name: Checkout the select-copilot-pat action folder
      with:
        persist-credentials: false
        sparse-checkout: .github/actions/select-copilot-pat
        sparse-checkout-cone-mode: true
        fetch-depth: 1

    - id: select-copilot-pat
      name: Select Copilot token from pool
      uses: ./.github/actions/select-copilot-pat
      env:
        # If the secret names are changed here, they must also be changed
        # in the `engine: env` case expression
        SECRET_0: ${{ secrets.COPILOT_PAT_0 }}
        SECRET_1: ${{ secrets.COPILOT_PAT_1 }}
        SECRET_2: ${{ secrets.COPILOT_PAT_2 }}
        SECRET_3: ${{ secrets.COPILOT_PAT_3 }}
        SECRET_4: ${{ secrets.COPILOT_PAT_4 }}
        SECRET_5: ${{ secrets.COPILOT_PAT_5 }}
        SECRET_6: ${{ secrets.COPILOT_PAT_6 }}
        SECRET_7: ${{ secrets.COPILOT_PAT_7 }}
        SECRET_8: ${{ secrets.COPILOT_PAT_8 }}
        SECRET_9: ${{ secrets.COPILOT_PAT_9 }}

# Add the pre-activation output of the randomly selected PAT
jobs:
  pre-activation:
    outputs:
      copilot_pat_number: ${{ steps.select-copilot-pat.outputs.copilot_pat_number }}

# Override the COPILOT_GITHUB_TOKEN expression used in the activation job
# Consume the PAT number from the pre-activation step and select the corresponding secret
engine:
  id: copilot
  env:
    # We cannot use line breaks in this expression as it leads to a syntax error in the compiled workflow
    # If none of the `COPILOT_PAT_#` secrets were selected, then the default COPILOT_GITHUB_TOKEN is used
    COPILOT_GITHUB_TOKEN: ${{ case(needs.pre_activation.outputs.copilot_pat_number == '0', secrets.COPILOT_PAT_0, needs.pre_activation.outputs.copilot_pat_number == '1', secrets.COPILOT_PAT_1, needs.pre_activation.outputs.copilot_pat_number == '2', secrets.COPILOT_PAT_2, needs.pre_activation.outputs.copilot_pat_number == '3', secrets.COPILOT_PAT_3, needs.pre_activation.outputs.copilot_pat_number == '4', secrets.COPILOT_PAT_4, needs.pre_activation.outputs.copilot_pat_number == '5', secrets.COPILOT_PAT_5, needs.pre_activation.outputs.copilot_pat_number == '6', secrets.COPILOT_PAT_6, needs.pre_activation.outputs.copilot_pat_number == '7', secrets.COPILOT_PAT_7, needs.pre_activation.outputs.copilot_pat_number == '8', secrets.COPILOT_PAT_8, needs.pre_activation.outputs.copilot_pat_number == '9', secrets.COPILOT_PAT_9, secrets.COPILOT_GITHUB_TOKEN) }}
```

## References

- [Agentic Workflow Imports][1]
- [Custom Steps][2]
- [Custom Jobs][3]
- [Job Outputs][4]
- [Engine Configuration][5]
- [Engine Environment Variables][6]
- [Case Function in Workflow Expressions][7]
- [Update agentic engine token handling to use user-provided secrets (github/gh-aw#18017)][8]

[1]: https://github.github.com/gh-aw/reference/imports/
[2]: https://github.github.com/gh-aw/reference/frontmatter/#custom-steps-steps
[3]: https://github.github.com/gh-aw/reference/frontmatter/#custom-jobs-jobs
[4]: https://github.github.com/gh-aw/reference/frontmatter/#job-outputs
[5]: https://github.github.com/gh-aw/reference/frontmatter/#ai-engine-engine
[6]: https://github.github.com/gh-aw/reference/engines/#engine-environment-variables
[7]: https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#case
[8]: https://github.com/github/gh-aw/pull/18017
