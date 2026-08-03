# Workflow CLI entry point. Resolves the workflow definition and the
# current state file via relative imports; the bash wrapper at
# scripts/nickel-cli is path-blind and just dispatches here.
{
  cli
    | doc "Returns the next step to execute given current state."
    =
      let workflow = import "../workflow.ncl" in
      let state = workflow.normalize_state (import "../../../.do-results.json") in
      workflow.cli state,

  cli_seed
    | doc "Returns the seeded step list for the given entry point."
    = fun from =>
      let workflow = import "../workflow.ncl" in
      let state = workflow.normalize_state (import "../../../.do-results.json") in
      workflow.cli_seed from state,
}
