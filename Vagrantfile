# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'yaml'

# Load configuration files
config_dir = File.dirname(__FILE__) + '/config'
nodes_config = YAML.load_file("#{config_dir}/nodes.yaml")
settings = YAML.load_file("#{config_dir}/settings.yaml")

# Validate configuration
unless nodes_config['nodes']
  puts "Error: No nodes defined in config/nodes.yaml"
  exit 1
end

# Function to check if custom box exists and get appropriate box
def get_box_for_node(hostname, base_box)
  box_file = File.dirname(__FILE__) + "/boxes/#{hostname}.box"
  
  # Only show messages during 'up' command, not for status/destroy/etc
  show_messages = ARGV.include?('up') && ENV['VAGRANT_QUIET'] != '1'
  
  if File.exist?(box_file)
    puts "Using custom box: #{hostname}.box" if show_messages
    box_file
  else
    puts "Using base box: #{base_box} (will provision)" if show_messages
    base_box
  end
end

# Function to determine if we should provision
def should_provision?(hostname)
  box_file = File.dirname(__FILE__) + "/boxes/#{hostname}.box"
  !File.exist?(box_file)  # Only provision if custom box doesn't exist
end

Vagrant.configure("2") do |config|
  # Base box from settings
  base_box = settings['vagrant']['box'] || 'bento/ubuntu-22.04'
  
  # Increase boot timeout for slower systems
  config.vm.boot_timeout = settings['vagrant']['boot_timeout'] || 600
  config.ssh.insert_key = settings['vagrant']['insert_key'] || false
  
  # VirtualBox specific settings
  config.vm.provider "virtualbox" do |vb|
    vb.gui = false
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
  end
  
  # Create VMs
  nodes_config['nodes'].each do |hostname, node_config|
    config.vm.define hostname do |node|
      node.vm.hostname = hostname
      
      # Set box (custom if available, base box otherwise)
      node.vm.box = get_box_for_node(hostname, base_box)
      
      # Network configuration - VirtualBox host-only network
      node.vm.network "private_network", ip: node_config['ip']
      
      # VM resources
      node.vm.provider "virtualbox" do |vb|
        vb.name = hostname
        vb.memory = node_config['memory']
        vb.cpus = node_config['cpus']
        vb.linked_clone = true
      end
      
      # Only provision if using base box (not custom box)
      if should_provision?(hostname)
        puts "Will provision #{hostname} from scratch" if ARGV.include?('up') && ENV['VAGRANT_QUIET'] != '1'
        
        # Environment variables for all provisioning scripts
        provision_env = {
          # Node-specific
          "NODE_NAME" => hostname,
          "NODE_ROLE" => node_config['role'],
          "NODE_IP" => node_config['ip'],
          
          # CVMFS settings
          "CVMFS_DOMAIN" => settings['cvmfs']['domain'],
          "REPOSITORY_NAME" => settings['cvmfs']['repository_name'],
          
          # All node IPs (for hosts file and service discovery)
          "GATEWAY_IP" => nodes_config['nodes']['cvmfs-gateway-stratum0']['ip'],
          "STRATUM0_IP" => nodes_config['nodes']['cvmfs-gateway-stratum0']['ip'],
          "STRATUM1_IP" => nodes_config['nodes']['cvmfs-stratum1']['ip'],
          "PROXY_IP" => nodes_config['nodes']['squid-proxy']['ip'],
          "PUBLISHER1_IP" => nodes_config['nodes']['cvmfs-publisher1']['ip'],
          "PUBLISHER2_IP" => nodes_config['nodes']['cvmfs-publisher2']['ip'],
          "CLIENT_IP" => nodes_config['nodes']['cvmfs-client']['ip'],
          
          # Service ports
          "GATEWAY_PORT" => settings['cvmfs']['gateway_port'].to_s,
          "PROXY_PORT" => settings['proxy']['port'].to_s,
          
          # Repository settings
          "REPO_OWNER" => settings['cvmfs']['repo_owner'] || 'vagrant'
        }
        
        # Base provisioning
        node.vm.provision "base", type: "shell", 
          path: "provisioning/common/base.sh",
          env: provision_env
        
        # Role-specific provisioning
        node.vm.provision "role", type: "shell",
          path: "provisioning/roles/#{node_config['role']}.sh",
          env: provision_env
        
        # Additional provisioning for publishers - Podman support
        if node_config['role'] == 'publisher'
          node.vm.provision "podman", type: "shell", inline: <<-SHELL
            echo "=== Installing Podman for container support ==="
            
            # Install Podman
            apt-get update
            apt-get install -y podman
            
            # Make container scripts executable
            chmod +x /vagrant/containers/publisher/run-container.sh
            
            # Create symlink for easy access
            ln -sf /vagrant/containers/publisher/run-container.sh /usr/local/bin/run-publisher-container
            
            # Create a helper script to switch between native and container mode
            cat > /usr/local/bin/publisher-mode << 'SCRIPT'
#!/bin/bash
case "$1" in
  native)
    echo "Switching to native mode..."
    podman stop cvmfs-publisher 2>/dev/null || true
    echo "Use: sudo systemctl start github-runner"
    ;;
  container)
    echo "Switching to container mode..."
    sudo systemctl stop github-runner 2>/dev/null || true
    echo "Use: run-publisher-container [GITHUB_REPO TOKEN]"
    ;;
  status)
    echo "=== Publisher Status ==="
    echo "Native service:"
    systemctl is-active github-runner || echo "  Not running"
    echo "Container:"
    podman ps | grep cvmfs-publisher || echo "  Not running"
    ;;
  *)
    echo "Usage: publisher-mode {native|container|status}"
    ;;
esac
SCRIPT
            chmod +x /usr/local/bin/publisher-mode
            
            # Create info file
            cat > /home/vagrant/CONTAINER_INFO.txt << 'INFO'
Publisher Container Support Enabled!
===================================

This publisher can run in two modes:

1. NATIVE MODE (default):
   - GitHub runner as systemd service
   - Direct CVMFS operations
   
2. CONTAINER MODE:
   - GitHub runner in Podman container
   - Isolated environment
   - Architecture detection at runtime

Commands:
  publisher-mode status     - Check current status
  publisher-mode native     - Switch to native mode
  publisher-mode container  - Switch to container mode
  
  run-publisher-container   - Run container (manual mode)
  run-publisher-container REPO TOKEN - Run with GitHub runner

Container operations:
  podman logs cvmfs-publisher    - View logs
  podman exec -it cvmfs-publisher bash - Get shell
  podman stop cvmfs-publisher    - Stop container

INFO
            chown vagrant:vagrant /home/vagrant/CONTAINER_INFO.txt
            
            echo
            echo "Podman installed! Container support is ready."
            echo "See ~/CONTAINER_INFO.txt for usage instructions."
          SHELL
        end
        
      else
        puts "Skipping provisioning for #{hostname} (using custom box)" if ARGV.include?('up') && ENV['VAGRANT_QUIET'] != '1'
      end
    end
  end
end
