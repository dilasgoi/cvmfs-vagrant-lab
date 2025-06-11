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

Vagrant.configure("2") do |config|
  # Use Bento box - more reliable for VirtualBox
  config.vm.box = settings['vagrant']['box'] || 'bento/ubuntu-22.04'
  
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
      
      # Network configuration - VirtualBox host-only network
      node.vm.network "private_network", ip: node_config['ip']
      
      # VM resources
      node.vm.provider "virtualbox" do |vb|
        vb.name = hostname
        vb.memory = node_config['memory']
        vb.cpus = node_config['cpus']
        vb.linked_clone = true
      end
      
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
    end
  end
end
