#!/usr/bin/env bash
set -euo pipefail

usage () {
  echo "Usage: rama-cluster.sh <deploy|destroy|plan|configure> [--singleNode] <cluster-name> [optional args]"
  echo ""
  echo "Commands:"
  echo "  deploy     - Create infrastructure and configure with Ansible"
  echo "  destroy    - Destroy the cluster"
  echo "  plan       - Show Terraform plan"
  echo "  configure  - Run Ansible only (requires existing inventory)"
  echo ""
  echo "Options:"
  echo "  --singleNode  - Use single-node deployment"
  echo ""
  echo "Extra arguments for Ansible can be specified with ANSIBLE_EXTRA_ARGS environment variable"
  echo "  ANSIBLE_EXTRA_ARGS=\"--check --limit conductor\""""
  echo ""
  exit 2
}

[[ $# -ge 2 ]] || usage

DIR=$(realpath "$(dirname "$0")")
CWD=$(pwd)

OP_NAME=$1
shift # remove first arg, OP_NAME

SINGLE_NODE=false

if [[ "$1" == "--singleNode" ]]; then
	SINGLE_NODE=true
	shift
fi

	
[[ $# -ge 1 ]] || usage

CLUSTER_NAME=$1
shift

WORKSPACE_NAME=${CLUSTER_NAME}

ROOT_DIR="$(realpath "${DIR}/..")"
if [[ "$SINGLE_NODE" = true ]]; then
   TF_ROOT_DIR="${ROOT_DIR}"/rama-cluster/single
else
   TF_ROOT_DIR="${ROOT_DIR}"/rama-cluster/multi
fi

HOME_CLUSTER_DIR="${HOME}/.rama/${CLUSTER_NAME}"

if [[ $CLUSTER_NAME == "default" ]]; then
    echo "Cluster name may not be \"default\""
    exit 2
fi

echo "Performing ${OP_NAME} ${CLUSTER_NAME}"

find_rama_tfvars_rec () {
  if test -f "./rama.tfvars"; then
    realpath "./rama.tfvars"
  else
    if [ "$(pwd)" = "/" ]; then
      echo "[ERROR] Could not find rama.tfvars file" >&2
      exit 1
    else
      pushd ..
      find_rama_tfvars_rec
      popd
    fi
  fi
}

find_rama_tfvars () {
  cd "$CWD"
  tfvars="$(find_rama_tfvars_rec)"
  echo "$tfvars"
}

get_tfvars_value () {
  # get line
  line=$(grep $2 $1)
  # get the value, then trim leading/trailing whitespace
  echo "${line#*=}" | xargs
}

# Ensure Python virtualenv exists for Ansible scripts
ensure_venv () {
  VENV_DIR="${ROOT_DIR}/ansible/.venv"
  REQUIREMENTS="${ROOT_DIR}/ansible/scripts/requirements.txt"

  if [[ ! -d "${VENV_DIR}" ]]; then
    echo "Creating Python virtualenv for Ansible scripts..."
    python3 -m venv "${VENV_DIR}"
  fi

  # Activate and install/update dependencies
  echo "Activating Python virtualenv for Ansible"
  source "${VENV_DIR}/bin/activate"
  pip install -q -r "${REQUIREMENTS}"
}

run_destroy () {
  cd ${TF_ROOT_DIR}
  tfvars="$(find_rama_tfvars)"
  terraform workspace select "${WORKSPACE_NAME}"
  terraform destroy -auto-approve \
    -parallelism=50 \
    -var-file "$tfvars" \
    -var-file ~/.rama/auth.tfvars \
    -var="cluster_name=$CLUSTER_NAME"
  terraform workspace select default
  terraform workspace delete "${WORKSPACE_NAME}"

  rm -f ~/.rama/rama-"${CLUSTER_NAME}"
  rm -rf ~/.rama/"${CLUSTER_NAME}"
  echo "Rama cluster destroyed."
  # ensure zero exit code
  return 0
}

confirm_destroy () {
  echo "WARNING: you are attempting to destroy a cluster. Are you sure you want to do this?"
  read -p "Enter the name of the cluster to confirm destroy: " cluster_name
  if [ "$cluster_name" = "$CLUSTER_NAME" ]; then
    echo "Destroying $cluster_name..."
    run_destroy
  else
    echo "Cluster name was not entered, preserving cluster."
  fi
}

# allow passing in of extra args to `terraform apply`
all_args="$@"
rest_args=("${all_args}")
rest_args_set=${rest_args:-}
if [ ! -z ${rest_args_set} ]; then
  tf_apply_args="${rest_args[@]}"
else
  tf_apply_args=""
fi

run_deploy () {
  cd ${TF_ROOT_DIR}
  tfvars="$(find_rama_tfvars)"
  terraform init ${TF_INIT_OPTS:-}
  terraform workspace select "${WORKSPACE_NAME}" &> /dev/null || terraform workspace new "${WORKSPACE_NAME}"
  terraform apply \
    -auto-approve \
    -parallelism=30 \
    -var-file "$tfvars" \
    -var-file ~/.rama/auth.tfvars \
    -var="cluster_name=${CLUSTER_NAME}" \
    $tf_apply_args

  # "Install" rama and your cluster config in your home directory so that you
  # can deploy modules with `rama-$CLUSTER_NAME deploy $MODULE_NAME`
  rm -rf ${HOME_CLUSTER_DIR}
  mkdir -p ${HOME_CLUSTER_DIR}

  # Save the outputs to the cluster directory
  terraform output -json > ${HOME_CLUSTER_DIR}/outputs.json

  # Generate Ansible inventory from Terraform output
  ANSIBLE_DIR="${ROOT_DIR}/ansible"
  INVENTORY_FILE="${HOME_CLUSTER_DIR}/inventory.yml"

  # Ensure Python virtualenv is set up
  ensure_venv

  if [[ "$SINGLE_NODE" = true ]]; then
    terraform output -json | python ${ANSIBLE_DIR}/scripts/generate_inventory.py --single > ${INVENTORY_FILE}
    PLAYBOOK="${ANSIBLE_DIR}/playbooks/single.yml"
  else
    terraform output -json | python ${ANSIBLE_DIR}/scripts/generate_inventory.py > ${INVENTORY_FILE}
    PLAYBOOK="${ANSIBLE_DIR}/playbooks/multi.yml"
  fi

  # Get variables from tfvars for Ansible
  rama_source_path="$(get_tfvars_value $tfvars rama_source_path)"
  zookeeper_url="$(get_tfvars_value $tfvars zookeeper_url)"
  license_source_path="$(get_tfvars_value $tfvars license_source_path)" || license_source_path=""
  rama_user="$(get_tfvars_value $tfvars username)"

  # Run Ansible playbook
  echo "Running Ansible playbook to configure the cluster..."
  ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg" ansible-playbook -i ${INVENTORY_FILE} ${PLAYBOOK} \
    -e "rama_source_path=${rama_source_path}" \
    -e "zookeeper_url=${zookeeper_url}" \
    -e "license_source_path=${license_source_path}" \
    -e "rama_user=${rama_user}" \
    -e "cluster_name=${CLUSTER_NAME}" \
    -e "local_cluster_dir=${HOME_CLUSTER_DIR}"

  # Copy rama files to home directory
  (
      cp ${rama_source_path} ${HOME_CLUSTER_DIR}/rama.zip
      cp ${tfvars} ${HOME_CLUSTER_DIR}
  )
  (
      cd ${HOME_CLUSTER_DIR}
      unzip rama.zip &> /dev/null
      rm rama.yaml
      rm rama.zip
  )

  # rama.yaml is now generated by Ansible in ${HOME_CLUSTER_DIR}/rama.yaml
  ln -fs ~/.rama/${CLUSTER_NAME}/rama ~/.rama/rama-${CLUSTER_NAME}
  echo "Rama cluster deployed, have fun."
  # ensure zero exit code
  return 0
}

run_plan () {
  cd ${TF_ROOT_DIR}
  tfvars="$(find_rama_tfvars)"
  terraform workspace select "${WORKSPACE_NAME}" &> /dev/null || terraform workspace new "${WORKSPACE_NAME}"
  terraform init ${TF_INIT_OPTS:-}
  terraform plan \
    -var-file "$tfvars" \
    -var-file ~/.rama/auth.tfvars \
    -var="cluster_name=${CLUSTER_NAME}" \
    $tf_apply_args
}

run_configure () {
  ANSIBLE_DIR="${ROOT_DIR}/ansible"
  INVENTORY_FILE="${HOME_CLUSTER_DIR}/inventory.yml"

  # Check if inventory exists
  if [[ ! -f "${INVENTORY_FILE}" ]]; then
    echo "[ERROR] Inventory file not found at ${INVENTORY_FILE}"
    echo "Run 'deploy' first to create the infrastructure, or regenerate inventory with:"
    echo "  cd ${TF_ROOT_DIR} && terraform output -json | python ${ANSIBLE_DIR}/scripts/generate_inventory.py > ${INVENTORY_FILE}"
    exit 1
  fi

  # Get tfvars for Ansible variables
  tfvars="$(find_rama_tfvars)"

  # Ensure Python virtualenv is set up
  ensure_venv

  if [[ "$SINGLE_NODE" = true ]]; then
    PLAYBOOK="${ANSIBLE_DIR}/playbooks/single.yml"
  else
    PLAYBOOK="${ANSIBLE_DIR}/playbooks/multi.yml"
  fi

  # Get variables from tfvars for Ansible
  rama_source_path="$(get_tfvars_value $tfvars rama_source_path)"
  zookeeper_url="$(get_tfvars_value $tfvars zookeeper_url)"
  license_source_path="$(get_tfvars_value $tfvars license_source_path)" || license_source_path=""
  rama_user="$(get_tfvars_value $tfvars username)"

  # Run Ansible playbook
  echo "Running Ansible playbook to configure the cluster..."
  ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg" ansible-playbook -i ${INVENTORY_FILE} ${PLAYBOOK} \
    -e "rama_source_path=${rama_source_path}" \
    -e "zookeeper_url=${zookeeper_url}" \
    -e "license_source_path=${license_source_path}" \
    -e "rama_user=${rama_user}" \
    -e "cluster_name=${CLUSTER_NAME}" \
    -e "local_cluster_dir=${HOME_CLUSTER_DIR}" \
    ${ANSIBLE_EXTRA_ARGS:-}

  echo "Ansible configuration complete."
  return 0
}

case "${OP_NAME}" in
  deploy)
    run_deploy
    ;;
  destroy)
    confirm_destroy
    ;;
  plan)
    run_plan
    ;;
  configure)
    run_configure
    ;;
  *)
    usage
    ;;
esac
