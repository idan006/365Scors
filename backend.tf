terraform {
  backend "s3" {
    bucket       = "365scores-idan-webapp-tfstate-577424505362-us-east-1"
    key          = "365scores-idan-webapp/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
