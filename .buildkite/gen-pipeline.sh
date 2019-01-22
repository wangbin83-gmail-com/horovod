#!/bin/bash

# exit immediately on failure, or if an undefined variable is used
set -eu

# our repository in AWS
repository=091976041309.dkr.ecr.us-east-1.amazonaws.com/buildkite

# list of all the tests
tests=( \
       test-cpu-openmpi-py2_7-tf1_1_0-keras2_0_0-torch0_4_0-pyspark2_1_2 \
       test-cpu-openmpi-py3_5-tf1_1_0-keras2_0_0-torch0_4_0-pyspark2_1_2 \
       test-cpu-openmpi-py3_6-tf1_1_0-keras2_0_0-torch0_4_0-pyspark2_1_2 \
       test-cpu-openmpi-py2_7-tf1_6_0-keras2_1_2-torch0_4_1-pyspark2_3_2 \
       test-cpu-openmpi-py3_5-tf1_6_0-keras2_1_2-torch0_4_1-pyspark2_3_2 \
       test-cpu-openmpi-py3_6-tf1_6_0-keras2_1_2-torch0_4_1-pyspark2_3_2 \
       test-cpu-openmpi-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-pyspark2_4_0 \
       test-cpu-openmpi-py3_5-tf1_12_0-keras2_2_2-torch1_0_0-pyspark2_4_0 \
       test-cpu-openmpi-py3_6-tf1_12_0-keras2_2_2-torch1_0_0-pyspark2_4_0 \
       test-cpu-openmpi-py2_7-tfhead-kerashead-torchhead-pyspark2_4_0 \
       test-cpu-openmpi-py3_6-tfhead-kerashead-torchhead-pyspark2_4_0 \
       test-cpu-mpich-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-pyspark2_4_0 \
       test-gpu-openmpi-py2_7-tf1_6_0-keras2_1_2-torch0_4_1-pyspark2_3_2 \
       test-gpu-openmpi-py3_5-tf1_6_0-keras2_1_2-torch0_4_1-pyspark2_3_2 \
       test-gpu-openmpi-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-pyspark2_4_0 \
       test-gpu-openmpi-py3_5-tf1_12_0-keras2_2_2-torch1_0_0-pyspark2_4_0 \
       test-gpu-openmpi-py2_7-tfhead-kerashead-torchhead-pyspark2_4_0 \
       test-gpu-openmpi-py3_6-tfhead-kerashead-torchhead-pyspark2_4_0 \
       test-gpu-mpich-py2_7-tf1_12_0-keras2_2_2-torch1_0_0-pyspark2_4_0 \
       )

build_test() {
  local test=$1

  echo "- label: ':docker: Build ${test}'"
  echo "  plugins:"
  echo "  - docker-compose#6b0df8a98ff97f42f4944dbb745b5b8cbf04b78c:"
  echo "      build: ${test}"
  echo "      image-repository: ${repository}"
  echo "      cache-from: ${test}:${repository}:${test}-latest"
  echo "      config: docker-compose.test.yml"
  echo "      push-retries: 3"
  echo "  timeout_in_minutes: 15"
  echo "  retry:"
  echo "    automatic: true"
  echo "  agents:"
  echo "    queue: builders"
}

cache_test() {
  local test=$1

  echo "- label: ':docker: Update ${test}-latest'"
  echo "  plugins:"
  echo "  - docker-compose#v2.6.0:"
  echo "      push: ${test}:${repository}:${test}-latest"
  echo "      config: docker-compose.test.yml"
  echo "      push-retries: 3"
  echo "  timeout_in_minutes: 5"
  echo "  retry:"
  echo "    automatic: true"
  echo "  agents:"
  echo "    queue: builders"
}

run_test() {
  local test=$1
  local queue=$2
  local label=$3
  local command=$4

  echo "- label: '${label}'"
  echo "  command: ${command}"
  echo "  plugins:"
  echo "  - docker-compose#v2.6.0:"
  echo "      run: ${test}"
  echo "      config: docker-compose.test.yml"
  echo "      pull-retries: 3"
  echo "  timeout_in_minutes: 5"
  echo "  retry:"
  echo "    automatic: true"
  echo "  agents:"
  echo "    queue: ${queue}"
}

# begin the pipeline.yml file
echo "steps:"

# build every test container
for test in ${tests[@]}; do
  build_test "${test}"
done

# wait for all builds to finish
echo "- wait"

# cache test containers if built from master
# TODO: replace with master
if [[ "${BUILDKITE_BRANCH}" == "buildkite" ]]; then
  for test in ${tests[@]}; do
    cache_test "${test}"
  done
fi

# run all the tests
for test in ${tests[@]}; do
  if [[ ${test} == *-cpu-* ]]; then
    queue=cpu-tests
  else
    queue=gpu-tests
  fi

  run_test "${test}" "${queue}" \
    ":pytest: Run PyTests (${test})" \
    "bash -c \"cd /horovod/test && (echo test_*.py | xargs -n 1 \\\$(cat /mpirun_command) pytest -v --capture=no)\""

  run_test "${test}" "${queue}" \
    ":muscle: Test TensorFlow MNIST (${test})" \
    "bash -c \"\\\$(cat /mpirun_command) python /horovod/examples/tensorflow_mnist.py\""

  if [[ ${test} != *"tf1_1_0"* && ${test} != *"tf1_6_0"* ]]; then
    run_test "${test}" "${queue}" \
      ":muscle: Test TensorFlow Eager MNIST (${test})" \
      "bash -c \"\\\$(cat /mpirun_command) python /horovod/examples/tensorflow_mnist_eager.py\""
  fi

  run_test "${test}" "${queue}" \
    ":muscle: Test Keras MNIST (${test})" \
    "bash -c \"\\\$(cat /mpirun_command) python /horovod/examples/keras_mnist_advanced.py\""

  run_test "${test}" "${queue}" \
    ":muscle: Test PyTorch MNIST (${test})" \
    "bash -c \"\\\$(cat /mpirun_command) python /horovod/examples/pytorch_mnist.py\""
done
