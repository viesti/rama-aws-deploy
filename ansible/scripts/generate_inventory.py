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

    # Build proxy args for private hosts (not bastion)
    proxy_args = None
    if 'bastion_host' in tf_output:
        bastion_host = tf_output['bastion_host']['value']
        rama_user = tf_output['rama_user']['value']

        # Add bastion as a targetable host (connects directly, no proxy)
        inventory['all']['children']['bastion'] = {
            'hosts': {
                'bastion-0': {
                    'ansible_host': bastion_host
                }
            }
        }

        # Build ProxyCommand for private hosts (applied per-group, not to all)
        if ssh_key_path:
            proxy_cmd = (
                f"ssh -i {ssh_key_path} -W %h:%p -o StrictHostKeyChecking=no "
                f"-o UserKnownHostsFile=/dev/null {rama_user}@{bastion_host}"
            )
            proxy_args = f'-o ProxyCommand="{proxy_cmd}"'
        else:
            proxy_args = f"-o ProxyJump={rama_user}@{bastion_host}"

    # Add ZooKeeper hosts
    if 'zookeeper_private_ips' in tf_output:
        zk_ips = tf_output['zookeeper_private_ips']['value']
        zk_group = {'hosts': {}}
        if proxy_args:
            zk_group['vars'] = {'ansible_ssh_common_args': proxy_args}
        for idx, ip in enumerate(zk_ips):
            zk_group['hosts'][f'zk-{idx}'] = {'ansible_host': ip}
        inventory['all']['children']['zookeeper'] = zk_group

    # Add conductor
    if 'conductor_private_ip' in tf_output:
        conductor_group = {
            'hosts': {
                'conductor-0': {
                    'ansible_host': tf_output['conductor_private_ip']['value']
                }
            }
        }
        if proxy_args:
            conductor_group['vars'] = {'ansible_ssh_common_args': proxy_args}
        inventory['all']['children']['conductor'] = conductor_group

    # Add supervisors
    if 'supervisor_private_ips' in tf_output:
        supervisor_ips = tf_output['supervisor_private_ips']['value']
        supervisor_group = {'hosts': {}}
        if proxy_args:
            supervisor_group['vars'] = {'ansible_ssh_common_args': proxy_args}
        for idx, ip in enumerate(supervisor_ips):
            supervisor_group['hosts'][f'supervisor-{idx}'] = {'ansible_host': ip}
        inventory['all']['children']['supervisor'] = supervisor_group

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
    ssh_key_path = None
    if 'private_ssh_key' in tf_output and tf_output['private_ssh_key']['value']:
        ssh_key_path = tf_output['private_ssh_key']['value']
        inventory['all']['vars']['ansible_ssh_private_key_file'] = ssh_key_path

    # Add bastion as a targetable host (for WireGuard, etc.)
    if 'bastion_host' in tf_output:
        bastion_host = tf_output['bastion_host']['value']
        inventory['all']['children']['bastion'] = {
            'hosts': {
                'bastion-0': {
                    'ansible_host': bastion_host
                }
            }
        }

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
