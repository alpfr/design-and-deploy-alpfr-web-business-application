#!/usr/bin/env bash
# Destroys everything deploy.sh created: the DNS and validation records (if Terraform made them),
# the certificate, the CloudFront distribution, the bucket policy, the site files and the bucket.
#
#   ./destroy.sh          Show what will be destroyed, then ask for confirmation.
#   ./destroy.sh --plan   Show what would be destroyed and stop.
#
# If alpfr.com points at this distribution, the site goes offline when this runs.
# DNS records created outside Terraform are NOT removed; delete or repoint them yourself.
set -euo pipefail
cd "$(dirname "$0")"

PLAN_ONLY=false
case "${1:-}" in
  --plan) PLAN_ONLY=true ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

for tool in terraform aws; do
  command -v "$tool" >/dev/null || { echo "$tool is not installed or not on PATH." >&2; exit 1; }
done
if [ ! -f terraform.tfstate ] && [ ! -d .terraform ]; then
  echo "No Terraform state here; nothing to destroy." >&2; exit 1
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
echo "AWS account: $ACCOUNT"

terraform init -input=false
terraform plan -destroy -input=false

if [ "$PLAN_ONLY" = true ]; then
  echo "Plan only; nothing was changed."; exit 0
fi

echo
echo "This permanently deletes the resources listed above in account $ACCOUNT."
echo "Removing a CloudFront distribution can take 15 minutes or more."
read -r -p "Type destroy alpfr.com to continue: " answer
[ "$answer" = "destroy alpfr.com" ] || { echo "Cancelled; nothing was changed."; exit 0; }

terraform destroy -input=false -auto-approve
echo "Destroyed. terraform.tfstate is kept as a record; it now lists no resources."
