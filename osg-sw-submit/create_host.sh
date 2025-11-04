# hosts are created from cobbler on provisioning, We could modify the host in the puppet run
# but somehow icinga2 api doesn't handle modifying hosts soomthly
# So we remove the host created from cobbler and readd it with puppet, with its proper configs

_python_bin=/usr/bin/python2

# Original script had a hardcoded password, use an argument to avoid leaking contents
# in public git repo.
PASSWORD=$1

# query to remove host and all its attributes
/usr/bin/curl --noproxy "*" -v -u director:$PASSWORD \
     -H 'Accept: application/json' -H 'X-HTTP-Method-Override: DELETE' -X POST \
     -k "https://icinga0000.chtc.wisc.edu:5665/v1/objects/hosts/osg-sw-submit.chtc.wisc.edu?cascade=1" | $_python_bin -m json.tool

sleep 10

# query to make a host object and zone on the master server,
# This is done by doing an upload package and uploading the conf file with the client config
# client zone and client endpoint
/usr/bin/curl --noproxy "*" -v -u director:$PASSWORD \
     -k "https://icinga0000.chtc.wisc.edu:5665/v1/config/packages/osg-sw-submit.chtc.wisc.edu" \
     -H 'Accept: application/json' -X POST | $_python_bin -m json.tool

sleep 10

/usr/bin/curl --noproxy "*" -v -u director:$PASSWORD \
     -k "https://icinga0000.chtc.wisc.edu:5665/v1/config/stages/osg-sw-submit.chtc.wisc.edu" \
     -H 'Accept: application/json' -X POST \
     -d '{ "files": { "zones.d/master/osg-sw-submit.chtc.wisc.edu.conf": "object Endpoint \"osg-sw-submit.chtc.wisc.edu\" { \n host = \"128.105.244.80\" \n} \nobject Zone \"osg-sw-submit.chtc.wisc.edu\" { \n endpoints = [ \"osg-sw-submit.chtc.wisc.edu\" ] \n parent = \"master\" \n}" } } ' | $_python_bin -m json.tool

sleep 60

# query to create host with all of its attributes
/usr/bin/curl --noproxy "*" -v -u director:$PASSWORD \
     -k "https://icinga0000.chtc.wisc.edu:5665/v1/objects/hosts/osg-sw-submit.chtc.wisc.edu" \
     -H 'Accept: application/json' -X PUT \
     -d '{ "templates": [ "generic-host" ], "attrs": { "address": "128.105.244.80", "vars.os" : "Linux", "vars.role" : "submit", "vars.location" : "3370A" } }' | $_python_bin -m json.tool
