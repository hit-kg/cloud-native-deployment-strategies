#!/usr/bin/env bash

#./test.sh si mesh-rollouts-test no rollouts.sandbox61.opentlc.com

# oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
# Add Argo CD Git Webhook to make it faster

waitpodup(){
  x=1
  test=""
  while [ -z "${test}" ]
  do 
    echo "Waiting ${x} times for pod ${1} in ns ${2}" $(( x++ ))
    sleep 1 
    test=$(oc get po -n ${2} | grep ${1})
  done
}

waitoperatorpod() {
  NS=openshift-operators
  waitpodup $1 ${NS}
  oc get pods -n ${NS} | grep ${1} | awk '{print "oc wait --for condition=Ready -n '${NS}' pod/" $1 " --timeout 300s"}' | sh
}

waitjaegerpod() {
  NS=openshift-distributed-tracing
  waitpodup $1 ${NS}
  oc get pods -n ${NS} | grep ${1} | awk '{print "oc wait --for condition=Ready -n '${NS}' pod/" $1 " --timeout 300s"}' | sh
}

rm -rf /tmp/deployment
mkdir /tmp/deployment
cd /tmp/deployment

git clone https://github.com/davidseve/cloud-native-deployment-strategies.git
cd cloud-native-deployment-strategies
#To work with a branch that is not main. ./test.sh no helm_base
if [ ${2:-no} != "no" ]
then
    git fetch
    git switch $2
fi
git checkout -b rollouts-mesh 
git push origin rollouts-mesh 

if [ ${3:-no} = "no" ]
then
    oc apply -f gitops/gitops-operator.yaml
    waitoperatorpod gitops

    #To work with a branch that is not main. ./test.sh no helm_base no rollouts.sandbox2229.opentlc.com
    if [ ${2:-no} != "no" ]
    then
        sed -i "s/HEAD/$2/g" canary-argo-rollouts-service-mesh/application-cluster-config.yaml
    fi

    sed -i '/pipeline.enabled/{n;s/.*/        value: "true"/}' canary-argo-rollouts-service-mesh/application-cluster-config.yaml

    oc apply -f canary-argo-rollouts-service-mesh/application-cluster-config.yaml --wait=true
    
    sleep 4m
    waitjaegerpod jaeger
    waitoperatorpod kiali
    waitoperatorpod istio
fi

sed -i 's/change_me/davidseve/g' canary-argo-rollouts-service-mesh/application-shop-canary-rollouts-mesh.yaml
sed -i "s/change_domain/$4/g" canary-argo-rollouts-service-mesh/application-shop-canary-rollouts-mesh.yaml

oc apply -f canary-argo-rollouts-service-mesh/application-shop-canary-rollouts-mesh.yaml --wait=true
sleep 2m
tkn pipeline start pipeline-blue-green-e2e-test --param NEW_IMAGE_TAG=v1.0.1 --param MODE=online --param LABEL=.version --param APP=products --param NAMESPACE=gitops --param JQ_PATH=.metadata --param MESH=true --workspace name=app-source,claimName=workspace-pvc-shop-cd-e2e-tests -n gitops --showlog

