#!/usr/bin/env python3
"""
Generate Ansible inventory from Terraform output.

Usage:
    terraform output -json | python generate_inventory.py [--single] > inventory.yml

Arguments:
    --single    Generate inventory for single-node deployment
"""

import json
import sys
import yaml


def generate_multi_inventory(tf_output):
    """Generate inventory for multi-node deployment."""
    inventory = {
        'all': {
            'vars': {
                'ansible_user': tf_output['rama_user']['value'],
            },
            'children': {}
        }
    }

    # Add private SSH key if specified
    ssh_key_path = None
    if 'private_ssh_key' in tf_output and tf_output['private_ssh_key']['value']:
        ssh_key_path = tf_output['private_ssh_key']['value']
        inventory['all']['vars']['ansible_ssh_private_key_file'] = ssh_key_path

    # Add bastion SSH args if bastion is present
    if 'bastion_host' in tf_output:
        bastion_host = tf_output['bastion_host']['value']
        rama_user = tf_output['rama_user']['value']

        # Build ProxyCommand for bastion jump with SSH key
        if ssh_key_path:
            # Use ProxyCommand instead of ProxyJump for better key handling
            proxy_cmd = (
                f"ssh -i {ssh_key_path} -W %h:%p -o StrictHostKeyChecking=no "
                f"-o UserKnownHostsFile=/dev/null {rama_user}@{bastion_host}"
            )
            inventory['all']['vars']['ansible_ssh_common_args'] = (
                f'-o ProxyCommand="{proxy_cmd}"'
            )
        else:
            inventory['all']['vars']['ansible_ssh_common_args'] = (
                f"-o ProxyJump={rama_user}@{bastion_host}"
            )

    # Add ZooKeeper hosts
    if 'zookeeper_private_ips' in tf_output:
        zk_ips = tf_output['zookeeper_private_ips']['value']
        inventory['all']['children']['zookeeper'] = {'hosts': {}}
        for idx, ip in enumerate(zk_ips):
            inventory['all']['children']['zookeeper']['hosts'][f'zk-{idx}'] = {
                'ansible_host': ip
            }

    # Add conductor
    if 'conductor_private_ip' in tf_output:
        inventory['all']['children']['conductor'] = {
            'hosts': {
                'conductor-0': {
                    'ansible_host': tf_output['conductor_private_ip']['value']
                }
            }
        }

    # Add supervisors
    if 'supervisor_private_ips' in tf_output:
        supervisor_ips = tf_output['supervisor_private_ips']['value']
        inventory['all']['children']['supervisor'] = {'hosts': {}}
        for idx, ip in enumerate(supervisor_ips):
            inventory['all']['children']['supervisor']['hosts'][f'supervisor-{idx}'] = {
                'ansible_host': ip
            }

    return inventory


def generate_single_inventory(tf_output):
    """Generate inventory for single-node deployment."""
    inventory = {
        'all': {
            'vars': {
                'ansible_user': tf_output['rama_user']['value'],
            },
            'children': {
                'rama': {
                    'hosts': {}
                },
                # For template compatibility, create alias groups
                'zookeeper': {
                    'hosts': {}
                },
                'conductor': {
                    'hosts': {}
                },
                'supervisor': {
                    'hosts': {}
                }
            }
        }
    }

    # Add private SSH key if specified
    if 'private_ssh_key' in tf_output and tf_output['private_ssh_key']['value']:
        inventory['all']['vars']['ansible_ssh_private_key_file'] = (
            tf_output['private_ssh_key']['value']
        )

    # Get the single instance IP
    if 'rama_ip' in tf_output:
        rama_ip = tf_output['rama_ip']['value']
        inventory['all']['children']['rama']['hosts']['rama'] = {
            'ansible_host': rama_ip
        }
        # Also add to alias groups for template compatibility
        inventory['all']['children']['zookeeper']['hosts']['rama'] = {
            'ansible_host': rama_ip
        }
        inventory['all']['children']['conductor']['hosts']['rama'] = {
            'ansible_host': rama_ip
        }
        inventory['all']['children']['supervisor']['hosts']['rama'] = {
            'ansible_host': rama_ip
        }

    return inventory


def main():
    # Check for --single flag
    single_node = '--single' in sys.argv

    # Read Terraform output from stdin
    tf_output = json.load(sys.stdin)

    # Generate appropriate inventory
    if single_node:
        inventory = generate_single_inventory(tf_output)
    else:
        inventory = generate_multi_inventory(tf_output)

    # Output YAML
    print(yaml.dump(inventory, default_flow_style=False, sort_keys=False))


if __name__ == '__main__':
    main()
