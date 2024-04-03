# tf-gcp-infra

My IaaC using Terraform for Google Cloud Platform for: [CYSE6225 Network Structures &amp; Cloud Computing](https://spring2024.csye6225.cloud/)

### Networking Setup
1. VPC Network:
   - Disabled auto-create 
   - Regional routing mode
   - No default routes
2. Subnet #1: webapp
   - /24 CIDR range
3. Subnet #2: db
   - /24 CIDR range
4. Attached Internet Gateway to the VPC for allowing incoming requests
5. VPC Peering Connection for connection to Private CloudSQL
6. VPC Serverless Access for connection to CloudSQL
7. Firewall, Ingress:
   - Allow only 8080
   - Deny all

### Database Set Up
PostgreSQL Private Cloud SQL attached to VPC

### Instance
Webapp compute instance attached to webapp subnet of VPC
   
### Event-Driven
Email Verification Event sent in PubSub 

### Cloud Functions
Sending Email Verification through Servless CLoud Function

### Identity and Access Management
Separate IAM roles for:
   - Creating resources
   - Logging & Metric FUnctionalities
   - Running Cloud FUnctions
   

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

## API & Services

### Enabled:

Used
- Compute Engine API
- Serverless VPC Access API
- Cloud Monitoring API
- Cloud Functions API
- Eventarc API
- Cloud Pub/Sub API
- Cloud Logging API
- Cloud Deployment Manager V2 API
- Cloud Run Admin API
- Cloud SQL Admin API
- Artifact Registry API
- Cloud Resource Manager API
- Identity and Access Management (IAM) API
- Service Networking API
- Cloud Build API
- Cloud DNS API
- Certificate Manager API

Unused:
- Cloud OS Login API					
- Cloud Storage					
- Container Registry API					
- Firewall Insights API					
- Google Cloud Storage JSON API					
- IAM Service Account Credentials API					
- Legacy Cloud Source Repositories API
- Service Usage API					
- Stackdriver API

## References:
1. [Install Chocolatey](https://docs.chocolatey.org/en-us/choco/setup)
2. [Install Terraform using Chocolatey](https://community.chocolatey.org/packages/terraform)
3. [Install gcloud cli](https://cloud.google.com/sdk/docs/install)
4. [Set up Terraform](https://developer.hashicorp.com/terraform/install?ajs_aid=ee087ad3-951d-4cf7-bcf4-ebbe422dd887&product_intent=terraform)

