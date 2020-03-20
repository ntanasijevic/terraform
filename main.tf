provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "example" {
  ami           = "ami-0cc89cd93fc3ece12"
  instance_type = "t2.micro"

  tags = {
    Name = "terraform-example"
  }
}
