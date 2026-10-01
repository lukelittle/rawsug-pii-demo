# Sourced by the other scripts: Terraform outputs as shell variables.
# shellcheck disable=SC2034  # used by the scripts that source this
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_CMD="$(command -v tofu 2>/dev/null || command -v terraform)"
tf_out() { "$TF_CMD" -chdir="$ROOT/terraform" output -raw "$1"; }
REGION="$(tf_out region)"
FUNCTION="$(tf_out function_name)"
API_URL="$(tf_out api_url)"
QUEUE_URL="$(tf_out review_queue_url)"
export AWS_REGION="$REGION"
