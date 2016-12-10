docker-compose rm -f
rm -r ./grouper/temp/ ./provisioner/temp/
mkdir -p ./grouper/temp/ ./provisioner/temp/

pushd ../CMUChangeLogConsumer
ant dist

popd
cp ../CMUChangeLogConsumer/build/cmuConsumer-1.0.tar.gz ./grouper/temp/
cp -r ../amq_ldap_provisioner/ ./provisioner/temp/amq_ldap_provisioner/

docker-compose build
