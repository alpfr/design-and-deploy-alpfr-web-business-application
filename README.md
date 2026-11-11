# alpfr.com business website

Source, infrastructure and documentation for the ALPFR Solutions website: a single static page
served from a private S3 bucket through CloudFront, deployed with Terraform.

## Contents

| Path | What it is |
| --- | --- |
| `index.html` | The whole site: one self-contained page (HTML, CSS and a small script) |
| `capabilities-statement.pdf` | Download linked from the Capabilities and Partners sections |
| `terraform/` | Terraform for the bucket, CloudFront distribution, certificate and DNS records |
| `terraform/deploy.sh` | Plan and apply, for the preview or the custom domain |
| `terraform/destroy.sh` | Tear everything down |
| `DEPLOY.md` | Deployment guide: preview, cutover, teardown |
| `ARCHITECTURE.md` | Architecture design, diagram, security and cost |

## Quick start

```bash
cd terraform
./deploy.sh --plan    # review what will be created
./deploy.sh           # preview deploy on a cloudfront.net URL; DNS is not touched
```

See `DEPLOY.md` for the cutover to alpfr.com.

## Status

- The Terraform and scripts have not yet been run against AWS; `./deploy.sh --plan` is the first real check.
- `index.html` still contains yellow-highlighted placeholders (search for `confirm`). Resolve them
  before pointing alpfr.com at the new site. The list is in `ARCHITECTURE.md` under "Pre-launch checklist".

## Share links (once live)

- `https://www.alpfr.com/#partners` opens at the section for prime contractors.
- `https://www.alpfr.com/?topic=teaming#contact` opens the contact form with teaming preselected.
