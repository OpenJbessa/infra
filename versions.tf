terraform {
  required_version = ">= 1.6"

  required_providers {
    hostinger = {
      source  = "hostinger/hostinger"
      version = "~> 0.1.23"
    }
  }

  # State local par défaut. ATTENTION : le state contient le token API et le mot
  # de passe root en clair — il est déjà exclu par .gitignore. Pour travailler à
  # plusieurs ou depuis la CI, basculer sur un backend distant chiffré.
  #
  # backend "s3" {
  #   bucket  = "mon-bucket-tfstate"
  #   key     = "hostinger/vps.tfstate"
  #   region  = "eu-west-3"
  #   encrypt = true
  # }
}
