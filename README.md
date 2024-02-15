# tf-gcp-infra

My IaaC using Terraform for: [CYSE6225 Network Structures &amp; Cloud Computing](https://spring2024.csye6225.cloud/)

## GCP Networking Setup

1. VPC Network:
   - Disabled auto-create 
   - Regional routing mode
   - No default routes
2. Subnet #1: webapp
   - /24 CIDR range
3. Subnet #2: db
   - /24 CIDR range
4. Attached Internet Gateway to the VPC

## How to build & run the application

1. Add your variables in ./terraform.tfvars

2. Terraform Initalization
   
```
terraform init
```

3. Terraform Validate
   
```
terraform validate
```

4. Terraform Apply
   
```
terraform apply
```

## References:
1. [Install Chocolatey](https://docs.chocolatey.org/en-us/choco/setup)
2. [Install Terraform using Chocolatey](https://community.chocolatey.org/packages/terraform)
3. [Install gcloud cli](https://cloud.google.com/sdk/docs/install)
4. [Set up Terraform](https://developer.hashicorp.com/terraform/install?ajs_aid=ee087ad3-951d-4cf7-bcf4-ebbe422dd887&product_intent=terraform)

