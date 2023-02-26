#!/bin/bash

# Get the list of namespaces to include
INCLUDE_NAMESPACES=$(kubectl get namespaces --all-namespaces -o jsonpath='{.items[*].metadata.name}')

# Get the list of namespaces to exclude (comma-separated list)
EXCLUDE_NAMESPACES="$1"

# Get the list of deployments to exclude (comma-separated list)
EXCLUDE_DEPLOYMENTS="$2"

# Filter out the excluded namespaces
IFS=',' read -ra EXCLUDE_NAMESPACE_ARRAY <<< "$EXCLUDE_NAMESPACES"
for NAMESPACE in ${EXCLUDE_NAMESPACE_ARRAY[@]}; do
  INCLUDE_NAMESPACES=$(echo "$INCLUDE_NAMESPACES" | grep -v "$NAMESPACE")
done

# Loop through each namespace and check the status of the pods in the deployments
for NAMESPACE in $INCLUDE_NAMESPACES; do
  # Get the list of deployments to include
  INCLUDE_DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')

  # Filter out the excluded deployments
  IFS=',' read -ra EXCLUDE_DEPLOYMENT_ARRAY <<< "$EXCLUDE_DEPLOYMENTS"
  for DEPLOYMENT in ${EXCLUDE_DEPLOYMENT_ARRAY[@]}; do
    INCLUDE_DEPLOYMENTS=$(echo "$INCLUDE_DEPLOYMENTS" | grep -v "$DEPLOYMENT")
  done

  # Loop through each deployment and check the status of the pods
  for DEPLOYMENT in $INCLUDE_DEPLOYMENTS; do
    PODS=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -o jsonpath='{.items[*].metadata.name}')
    for POD in $PODS; do
      STATUS=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.phase}')

      # Check if the pod is in a "Not Running" state and has been for at least 1 hour
      if [ "$STATUS" == "Unknown" ] || [ "$STATUS" == "Error" ] || [ "$STATUS" == "CrashLoopBackOff" ]
      then
        AGE=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.metadata.creationTimestamp}' | cut -d'.' -f1)
        AGE_SECS=$(($(date +%s) - $(date -d "$AGE" +%s)))
        if [ $AGE_SECS -ge 3600 ]
        then
          # Scale down the deployment
          kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=0
        fi
      fi
    done
  done
done

