#!/bin/bash
#set -x
DIRNAME=$(dirname $(realpath ${BASH_SOURCE[0]}))
source ${DIRNAME}/commons/utils.sh

readConfig ${ENV_CONFIG_FILE}
readConfig ${DEPLOYMENT_CONFIG_FILE} -r Common
readConfig ${INFRA_CONFIG_FILE}

echo "{
\"status\": \"INACTIVE\"
}" > inactive.json

cat <<EOF > offboard.sh
#!/bin/sh

TENANT=\$(/tmp/run.sh get tenant | grep TYPE -A 20 | grep -v TYPE)

OLD_IFS=\$IFS
IFS=\$'\n'
for EACH_TENANT in \$TENANT
do
        IFS=\$OLD_IFS
        TENANT_ID=\$(echo "\$EACH_TENANT" | awk '{print \$3}' | sed 's/|//')
        TENANT_STATUS=\$(echo "\$EACH_TENANT" | awk '{print \$4}' | sed 's/|//')
  /tmp/tctl get tenant-service \$TENANT_ID
  SERVICE_LIST=\$(/tmp/tctl get tenant-service \$TENANT_ID| grep STATUS -A 20 | grep -v STATUS | awk '{print \$4}' | sed 's/|//')
  for EACH_SERVICE in \$SERVICE_LIST
  do
    echo "running /tmp/tctl offboard tenant-service \$TENANT_ID -i \$EACH_SERVICE"
    echo yes | /tmp/tctl offboard tenant-service \$TENANT_ID -i \$EACH_SERVICE
    [[ \$? -ne 0 ]] && SERVICE_OFFBOARD="false"
  done
  [[ -n "$SERVICE_OFFBOARD" ]] && echo "skiping tenant offboard" && exit 1
        echo "running /tmp/tctl update tenant \$TENANT_ID -f inactive.json"
  /tmp/tctl update tenant \$TENANT_ID -f inactive.json
        echo "running /tmp/tctl offboard tenant \$TENANT_ID"
  echo yes | /tmp/tctl offboard tenant \$TENANT_ID
        LATEST_TENANT=\$(/tmp/tctl get tenant \$TENANT_ID | grep TYPE -A 20 | grep -v TYPE)
        if [ -z "\$LATEST_TENANT" ]; then
                echo "\$TENANT_ID off-board successfully"
        else
                echo "\$TENANT_ID off-board failed"
        fi
  /tmp/tctl get tenant-service \$TENANT_ID
done
EOF


${KUBECTL_BIN} -n ${NAMESPACE} create cm offboard-cm --from-file=offboard.sh --dry-run=client -o yaml | ${KUBECTL_BIN} -n ${NAMESPACE}  apply -f -
${KUBECTL_BIN} -n ${NAMESPACE} create cm inactive-cm  --from-file=inactive.json --dry-run=client -o yaml | ${KUBECTL_BIN} -n ${NAMESPACE}  apply -f -


#result=$(${KUBECTL_BIN} get po -n ${NAMESPACE} 2>/dev/null | grep "ade-tenant-management.*Running")
#if [ $? -ne 0 ]; then

result=$(${KUBECTL_BIN} version --short 2>&1 | grep -i "server version" | cut -d: -f2 | cut -d. -f2)
if [[ ${result} < 25 ]]; then
cat <<EOF | ${KUBECTL_BIN} apply -n ${NAMESPACE} -f - >/dev/null
  apiVersion: batch/v1
  kind: Job
  metadata:
    name: ade-tenant-management
  spec:
    backoffLimit: 4
    #replicas: 1
    #selector:
    #  matchLabels:
    #    app: ade-tenant-management
    template:
      #metadata:
      #  labels:
      #    app: ade-tenant-management
      spec:
        restartPolicy: Never
        volumes:
          - name: offboard-vol
            configMap:
              name: offboard-cm
              optional: false
              defaultMode: 0777
          - name: inactive-vol
            configMap:
              name: inactive-cm
              optional: false
        containers:
        - env:
            - name: APP_URL
              value:  http://tms:8000
            - name: SERVICE_PORT
              value: "8000"
            - name: CLIENT_ID
              value: "123"
            - name: CLIENT_SECRET
              value: "123"
            - name: RSSO_URL
              valueFrom:
                configMapKeyRef:
                  key: rssourl
                  name: rsso-admin-tas
            - name: COMMAND
              value: get
            - name: ENTITY
              value: tenant
            - name: FULL_VALUE
              value: ""
            - name: FLAG
              value: "-o"
            - name: JSON_VALUE
              value:
          name: ade-tenant-management
          volumeMounts:
          - name: offboard-vol
            mountPath: /tmp/offboard.sh
            subPath: offboard.sh
          - name: inactive-vol
            mountPath: /tctl/inactive.json
            subPath: inactive.json
          image: ${IMAGE_REGISTRY_HOST}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_REGISTRY_ORG}:tctlrest-${TCTL_REST_VER}
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
                cp /tctl/* /tmp/
                sh -x /tmp/offboard.sh
                #while true; do sleep 50; done
                echo "bmc_done"
          resources:
            limits:
              cpu: 500m
              memory: 512Mi
            requests:
              cpu: 100m
              memory: 128Mi
        imagePullSecrets:
        - name: bmc-dtrhub
        #securityContext:
        #  fsGroup: 1000
        #  runAsGroup: 1000
        #  runAsUser: 1000
EOF
else
cat <<EOF | ${KUBECTL_BIN} apply -n ${NAMESPACE} -f - >/dev/null
  apiVersion: batch/v1
  kind: Job
  metadata:
    name: ade-tenant-management
  spec:
    backoffLimit: 4
    #replicas: 1
    #selector:
    #  matchLabels:
    #    app: ade-tenant-management
    template:
      #metadata:
      #  labels:
      #    app: ade-tenant-management
      spec:
        restartPolicy: Never
        volumes:
          - name: offboard-vol
            configMap:
              name: offboard-cm
              optional: false
              defaultMode: 0777
          - name: inactive-vol
            configMap:
              name: inactive-cm
              optional: false
        containers:
        - env:
            - name: APP_URL
              value:  http://tms:8000
            - name: SERVICE_PORT
              value: "8000"
            - name: CLIENT_ID
              value: "123"
            - name: CLIENT_SECRET
              value: "123"
            - name: RSSO_URL
              valueFrom:
                configMapKeyRef:
                  key: rssourl
                  name: rsso-admin-tas
            - name: COMMAND
              value: get
            - name: ENTITY
              value: tenant
            - name: FULL_VALUE
              value: ""
            - name: FLAG
              value: "-o"
            - name: JSON_VALUE
              value:
          name: ade-tenant-management
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          volumeMounts:
          - name: offboard-vol
            mountPath: /tmp/offboard.sh
            subPath: offboard.sh
          - name: inactive-vol
            mountPath: /tctl/inactive.json
            subPath: inactive.json
          image: ${IMAGE_REGISTRY_HOST}/${IMAGE_REGISTRY_PROJECT}/${IMAGE_REGISTRY_ORG}:tctlrest-${TCTL_REST_VER}
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
                cp /tctl/* /tmp/
                sh -x /tmp/offboard.sh
                #while true; do sleep 50; done
                echo "bmc_done"
          resources:
            limits:
              cpu: 500m
              memory: 512Mi
            requests:
              cpu: 100m
              memory: 128Mi
        imagePullSecrets:
        - name: bmc-dtrhub
        #securityContext:
        #  fsGroup: 1000
        #  runAsGroup: 1000
        #  runAsUser: 1000
EOF

fi

# wait for job to complete and print logs
sleep 10 
${KUBECTL_BIN} -n ${NAMESPACE} logs jobs/ade-tenant-management
