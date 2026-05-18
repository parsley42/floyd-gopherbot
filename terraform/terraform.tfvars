project_id       = "floyd-chatapi"
region           = "us-central1"
zone             = "us-central1-a"
bot_name         = "floyd"

gopherbot_version = "latest"
gopherbot_nobody  = true

machine_type       = "e2-micro"
boot_disk_size_gb  = 20

network_name    = "gopherbot-net"
subnetwork_name = "gopherbot-subnet"
subnetwork_cidr = "10.42.0.0/24"

enable_ssh_ingress = false

# Used only when enable_ssh_ingress = true.
allow_ssh_cidrs = [
# "35.235.240.0/20"
]

create_static_ip = true

enable_vpn         = true
wireguard_port     = 42427
vpn_cidr           = "10.77.0.1/24"
enable_firewall    = true

vm_service_account_id = "gopherbot-vm"

# Existing secret that contains your full .env file.
robot_env_secret_name = "floyd-env"

# Required when enable_vpn = true.
wireguard_private_key_secret_name = "floyd-wireguard-private-key"

systemd_timeout_stop_sec = 600

labels = {
  app   = "gopherbot"
  robot = "floyd"
}
