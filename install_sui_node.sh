#!/bin/bash

# Define a function to check if a command exists
exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if curl is installed, and if not, install it
if ! exists curl; then
  sudo apt update && sudo apt install curl -y < "/dev/null"
fi

# Source .bash_profile if it exists
bash_profile="$HOME/.bash_profile"
if [ -f "$bash_profile" ]; then
  . "$HOME/.bash_profile"
fi

# Download and run scripts to set up swapfile and install necessary software

echo -e "\n\e[42mInstall software\e[0m\n" && sleep 1
apt-get update && DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y --no-install-recommends tzdata git ca-certificates curl build-essential libssl-dev pkg-config libclang-dev cmake jq

# Install Rust
echo -e "\n\e[42mInstall Rust\e[0m\n" && sleep 1
sudo curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"

# Remove existing directories and files, and clone sui repository
rm -rf /var/sui/db /var/sui/genesis.blob "$HOME/sui"
mkdir -p /var/sui/db
cd "$HOME"
git clone https://github.com/MystenLabs/sui.git
cd sui
git remote add upstream https://github.com/MystenLabs/sui
git fetch upstream
git checkout --track upstream/devnet

# Copy fullnode-template.yaml and download genesis.blob file
cp crates/sui-config/data/fullnode-template.yaml /var/sui/fullnode.yaml
wget -O /var/sui/genesis.blob https://github.com/MystenLabs/sui-genesis/raw/main/devnet/genesis.blob

# Modify fullnode.yaml file
sed -i.bak "s/db-path:.*/db-path: \"\/var\/sui\/db\"/ ; s/genesis-file-location:.*/genesis-file-location: \"\/var\/sui\/genesis.blob\"/" /var/sui/fullnode.yaml
sed -i.bak 's/127.0.0.1/0.0.0.0/' /var/sui/fullnode.yaml

# Build and move sui-node and sui binaries to /usr/local/bin
cargo build --release
mv "$HOME/sui/target/release/sui-node" /usr/local/bin/ || exit
mv "$HOME/sui/target/release/sui" /usr/local/bin/ || exit

# Create and move systemd unit file, and restart systemd-journald, daemon-reload, and enable suid service
echo "[Unit]
Description=Sui Node
After=network.target

[Service]
User=$USER
Type=simple
ExecStart=/usr/local/bin/sui-node --config-path /var/sui/fullnode.yaml
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target" > "$HOME/suid.service"

mv "$HOME/suid.service" /etc/systemd/system/
sudo tee <<EOF >/dev/null /etc/systemd/journald.conf
Storage=persistent
EOF
sudo systemctl restart systemd-journald
sudo systemctl daemon-reload
sudo systemctl enable suid
sudo systemctl restart suid

# Check if suid service is running
