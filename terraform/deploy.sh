#!/usr/bin/env bash
# Deploys alpfr.com (S3 + CloudFront, and optionally the certificate and DNS) with Terraform.
#
#   ./deploy.sh                          Preview deploy on the cloudfront.net URL. No DNS change.
#   ./deploy.sh --domain                 Also request the certificate and attach alpfr.com + www.
#   ./deploy.sh --domain --zone-id Z123  Same, and create the Route 53 records (THIS IS THE CUTOVER).
#   ./deploy.sh --plan                   Show the plan and stop.
#   ./deploy.sh --invalidate             After applying, clear the CloudFront cache immediately.
#   ./deploy.sh --yes                    Skip the confirmation prompt.
#
# Options can be combined. Re-run any time index.html changes.
set -euo pipefail
cd "$(dirname "$0")"

DOMAIN=false; ZONE_ID=""; PLAN_ONLY=false; INVALIDATE=false; ASSUME_YES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --domain)     DOMAIN=true ;;
    --zone-id)    ZONE_ID="${2:?--zone-id needs a hosted zone ID}"; shift ;;
    --plan)       PLAN_ONLY=true ;;
    --invalidate) INVALIDATE=true ;;
    --yes)        ASSUME_YES=true ;;
    -h|--help)    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
if [ -n "$ZONE_ID" ] && [ "$DOMAIN" = false ]; then
  echo "--zone-id only applies together with --domain." >&2; exit 2
fi

for tool in terraform aws; do
  command -v "$tool" >/dev/null || { echo "$tool is not installed or not on PATH." >&2; exit 1; }
done
for f in ../index.html ../capabilities-statement.pdf; do
  [ -f "$f" ] || { echo "Missing site file: $f" >&2; exit 1; }
done

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
echo "AWS account: $ACCOUNT"
echo "Mode:        $([ "$DOMAIN" = true ] && echo "custom domain" || echo "preview only")$([ -n "$ZONE_ID" ] && echo " + Route 53 records in $ZONE_ID")"

if grep -q 'class="confirm"\|status confirm' ../index.html && [ "$DOMAIN" = true ]; then
  echo
  echo "WARNING: index.html still contains yellow 'confirm' placeholders."
  echo "         Visitors to alpfr.com would see them."
fi

VARS=(-var "enable_custom_domain=$DOMAIN" -var "route53_zone_id=$ZONE_ID")

terraform init -input=false
terraform validate

# DNS hosted outside Route 53: the certificate must exist before its validation records can be shown,
# and those records must be added by hand before the full apply can finish.
if [ "$DOMAIN" = true ] && [ -z "$ZONE_ID" ] && [ "$PLAN_ONLY" = false ] \
   && ! terraform state list 2>/dev/null | grep -q '^aws_acm_certificate_validation\.site'; then
  echo
  echo "Step 1 of 2: requesting the certificate for alpfr.com and www.alpfr.com."
  terraform apply -input=false "${VARS[@]}" -target=aws_acm_certificate.site -auto-approve
  echo
  echo "Add these CNAME records at your DNS host:"
  terraform output certificate_validation_records
  read -r -p "Press Enter once the records are added (the next step waits until the certificate is issued)... " _
  echo "Step 2 of 2: attaching the domain to the distribution."
fi

terraform plan -input=false "${VARS[@]}" -out=tfplan

if [ "$PLAN_ONLY" = true ]; then
  rm -f tfplan; echo "Plan only; nothing was changed."; exit 0
fi

if [ "$ASSUME_YES" = false ]; then
  echo
  [ -n "$ZONE_ID" ] && echo "This will overwrite the A/AAAA records for alpfr.com and www.alpfr.com."
  read -r -p "Apply this plan to account $ACCOUNT? Type yes to continue: " answer
  [ "$answer" = "yes" ] || { rm -f tfplan; echo "Cancelled; nothing was changed."; exit 0; }
fi

terraform apply -input=false tfplan
rm -f tfplan

if [ "$INVALIDATE" = true ]; then
  aws cloudfront create-invalidation \
    --distribution-id "$(terraform output -raw distribution_id)" --paths "/*" >/dev/null
  echo "Cache invalidation started."
fi

echo
echo "Preview URL: $(terraform output -raw preview_url)"
if [ "$DOMAIN" = true ] && [ -z "$ZONE_ID" ]; then
  echo "DNS is not managed here. At your DNS host, point www (CNAME) and alpfr.com"
  echo "(ALIAS/ANAME, or a redirect to www) at the cloudfront.net domain above."
fi
