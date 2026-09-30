# Sourced by the other scripts: Terraform outputs as shell variables.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_out() { terraform -chdir="$ROOT/terraform" output -raw "$1"; }
REGION="$(tf_out region)"
FUNCTION="$(tf_out function_name)"
API_URL="$(tf_out api_url)"
QUEUE_URL="$(tf_out review_queue_url)"
LOG_GROUP="$(tf_out lambda_log_group)"
export AWS_REGION="$REGION"
