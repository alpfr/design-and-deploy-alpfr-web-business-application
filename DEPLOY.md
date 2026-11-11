# Deploying alpfr.com with Terraform (S3 + CloudFront)

Everything is in `terraform/`. Two stages: a preview that leaves the live site alone, then the cutover.

Requirements: Terraform 1.5+, AWS CLI signed in to the account that should own the site.

## Scripts

Both scripts live in `terraform/` and wrap Terraform, so they cover every AWS resource the site uses.

| Command | What it does |
| --- | --- |
| `./deploy.sh` | Preview deploy on the `cloudfront.net` URL. No DNS change. |
| `./deploy.sh --plan` | Show the plan and stop. |
| `./deploy.sh --domain --zone-id ZXXXX` | Cutover with Route 53: certificate, hostnames, and A/AAAA records for alpfr.com and www. |
| `./deploy.sh --domain` | Cutover with DNS hosted elsewhere: requests the certificate, prints the validation records, waits for you to add them, then attaches the hostnames. You then point DNS at the distribution yourself. |
| `./deploy.sh --invalidate` | Add to any deploy to clear the CloudFront cache at once. |
| `./destroy.sh --plan` | Show what would be destroyed and stop. |
| `./destroy.sh` | Destroy everything after you type `destroy alpfr.com`. |

`deploy.sh` checks the tools and site files, shows the AWS account, runs `init`, `validate` and `plan`,
and asks for `yes` before applying. Re-run it whenever `index.html` changes; visitors see the change
within 5 minutes. New files must be added to `site_files` in `main.tf`.

**Pricing plan:** the distribution is created pay-as-you-go. To use the $0/month flat-rate Free plan,
switch the plan on the distribution in the CloudFront console.

## Stage 1: preview

```bash
cd ~/Downloads/scripts/alpfr-website/terraform
./deploy.sh --plan     # first real check of the configuration
./deploy.sh
```

## Stage 2: cutover to alpfr.com

Do this only after the yellow-highlighted items in `index.html` are resolved (search for `confirm`).
Note the current DNS records for `alpfr.com` and `www` first, so you can roll back.

```bash
./deploy.sh --domain --zone-id ZXXXXXXXXXXXXX   # DNS in Route 53
./deploy.sh --domain                            # DNS hosted elsewhere
```

Check `https://www.alpfr.com` and `https://alpfr.com`, and send a test consultation request.
To roll back, restore the DNS records you noted.

## Teardown

`./destroy.sh` removes the Route 53 records Terraform created, the certificate, the distribution,
the bucket policy, the site files and the bucket. If alpfr.com points at the distribution, the site
goes offline. DNS records created outside Terraform are not removed.

## No VPC

This architecture has no VPC. S3 and CloudFront are AWS-managed services that sit outside any VPC,
and a static site runs no servers, so there are no subnets, gateways or security groups to create
or destroy. A VPC only becomes relevant if the site later gains a backend that needs private
networking (for example containers or a database).

## State

Terraform state is stored locally in `terraform/terraform.tfstate` and is excluded from git by
`terraform/.gitignore`. Keep that file; without it Terraform loses track of what it created.
Move to an S3 backend if more than one person will deploy.
