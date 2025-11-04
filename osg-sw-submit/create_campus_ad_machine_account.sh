echo "\"sudo kinitnit <NETID>-ou@AD.WISC.EDU\"" must be ran prior to executing this script" 2>&1
echo "\"sudo kdestroy\" should be ran afterwards\" 2>&1
/usr/bin/msktutil create \
  --verbose \
  --account-name "${HOSTNAME%%.*}" \
  --no-reverse-lookups \
  --base "OU=Computers,OU=CHTC,OU=orgUnits"
