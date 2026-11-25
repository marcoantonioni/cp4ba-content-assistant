# cp4ba-content-assistant

## Install examples

Install custom cluster
```bash

export CP4BA_INST_CACMS_AIPROVIDER_API_KEY=""
export CP4BA_INST_CACMS_AIPROVIDER_SPACE_ID=""

_PTC=/home/$USER/cp4ba-projects/cp4ba-installations/configs26
CONFIG_FILE=${_PTC}/env1-authoring-baw-cacms.properties
./cp4ba-content-assistant.sh -c ${CONFIG_FILE} -k install
```
