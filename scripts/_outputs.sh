# Sourced by the other scripts: Terraform outputs as shell variables.
# shellcheck disable=SC2034  # used by the scripts that source this
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_out() { terraform -chdir="$ROOT/terraform" output -raw "$1"; }
REGION="$(tf_out region)"
FUNCTION="$(tf_out function_name)"
API_URL="$(tf_out api_url)"
QUEUE_URL="$(tf_out review_queue_url)"
export AWS_REGION="$REGION"
