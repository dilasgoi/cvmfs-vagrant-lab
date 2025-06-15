#!/bin/bash

# Box Management Script for CVMFS Vagrant Environment

# Find project root by looking for Vagrantfile
find_project_root() {
    local dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/Vagrantfile" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    
    echo "Error: Could not find Vagrantfile in any parent directory" >&2
    exit 1
}

PROJECT_ROOT="$(find_project_root)"
BOXES_DIR="$PROJECT_ROOT/boxes"
CONFIG_DIR="$PROJECT_ROOT/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create boxes directory if it doesn't exist
mkdir -p "$BOXES_DIR"

# Function to get node names from nodes.yaml
get_node_names() {
    local nodes_file="$CONFIG_DIR/nodes.yaml"
    
    if [[ -f "$nodes_file" ]]; then
        # Extract node names from YAML (lines that start with 2 spaces and contain a colon)
        grep -E "^  [a-zA-Z0-9_-]+:" "$nodes_file" | sed 's/:.*$//' | sed 's/^  //'
    else
        echo "Error: $nodes_file not found" >&2
        echo "Current directory: $(pwd)" >&2
        echo "Config directory contents:" >&2
        ls -la "$CONFIG_DIR" 2>&1 >&2 || echo "Config directory doesn't exist" >&2
        exit 1
    fi
}

# Function to package all VMs
package_all() {
    echo -e "${BLUE}Packaging all VMs into custom boxes...${NC}"
    
    for node in $(get_node_names); do
        echo -e "${YELLOW}Packaging $node...${NC}"
        
        # Check if VM is running
        if (cd "$PROJECT_ROOT" && VAGRANT_QUIET=1 vagrant status "$node" 2>/dev/null) | grep -q "running"; then
            # Clean up VM before packaging
            echo "Cleaning up $node before packaging..."
            (cd "$PROJECT_ROOT" && VAGRANT_QUIET=1 vagrant ssh "$node" -c "
                sudo apt-get clean > /dev/null 2>&1 || true
                sudo rm -rf /var/log/*.log > /dev/null 2>&1 || true
                sudo rm -rf /tmp/* > /dev/null 2>&1 || true
                history -c > /dev/null 2>&1 || true
            " 2>/dev/null)
            
            # Package the VM
            echo "Packaging $node into box file..."
            (cd "$PROJECT_ROOT" && VAGRANT_QUIET=1 vagrant package "$node" --output "$BOXES_DIR/$node.box" &>/dev/null)
            
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}Successfully packaged $node${NC}"
            else
                echo -e "${RED}Failed to package $node${NC}"
            fi
        else
            echo -e "${YELLOW}$node is not running, skipping...${NC}"
        fi
        echo ""
    done
}

# Function to package specific VM
package_node() {
    local node="$1"
    
    if [[ -z "$node" ]]; then
        echo -e "${RED}Error: No node name provided${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Packaging $node...${NC}"
    
    if (cd "$PROJECT_ROOT" && VAGRANT_QUIET=1 vagrant status "$node" 2>/dev/null) | grep -q "running"; then
        # Clean up before packaging
        (cd "$PROJECT_ROOT" && VAGRANT_QUIET=1 vagrant ssh "$node" -c "
            sudo apt-get clean > /dev/null 2>&1 || true
            sudo rm -rf /var/log/*.log > /dev/null 2>&1 || true
            sudo rm -rf /tmp/* > /dev/null 2>&1 || true
            history -c > /dev/null 2>&1 || true
        " 2>/dev/null)
        
        (cd "$PROJECT_ROOT" && VAGRANT_QUIET=1 vagrant package "$node" --output "$BOXES_DIR/$node.box" &>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}Successfully packaged $node${NC}"
        else
            echo -e "${RED}Failed to package $node${NC}"
        fi
    else
        echo -e "${RED}$node is not running${NC}"
    fi
}

# Function to clean boxes
clean_boxes() {
    echo -e "${BLUE}Cleaning custom boxes...${NC}"
    
    for node in $(get_node_names); do
        echo -e "${YELLOW}Removing ${node}.box...${NC}"
        rm -f "$BOXES_DIR/$node.box"
    done
    
    echo -e "${GREEN}Cleaned all custom boxes${NC}"
}

# Function to list available boxes
list_boxes() {
    echo -e "${BLUE}Available custom boxes:${NC}"
    echo ""
    
    for node in $(get_node_names); do
        box_file="$BOXES_DIR/$node.box"
        
        file_exists="No"
        
        if [[ -f "$box_file" ]]; then
            file_exists="Yes"
            size=$(du -h "$box_file" | cut -f1)
        else
            size="N/A"
        fi
        
        echo -e "  $node:"
        echo -e "    File exists: $file_exists ($size)"
        echo ""
    done
}

# Function to show usage
usage() {
    echo "Usage: $0 {package-all|package <node>|clean|list}"
    echo ""
    echo "Commands:"
    echo "  package-all     Package all running VMs into custom boxes"
    echo "  package <node>  Package specific node into custom box"
    echo "  clean          Remove all custom boxes"
    echo "  list           List status of custom boxes"
    echo ""
    echo "Available nodes:"
    for node in $(get_node_names); do
        echo "  - $node"
    done
}

# Main script logic
case "$1" in
    package-all)
        package_all
        ;;
    package)
        package_node "$2"
        ;;
    clean)
        clean_boxes
        ;;
    list)
        list_boxes
        ;;
    *)
        usage
        exit 1
        ;;
esac
