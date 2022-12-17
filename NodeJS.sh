#!/bin/bash

user=$1
domain=$2
ip=$3
home=$4
docroot=$5

#default script name
mainScript="start"
nodeDir="$home/$user/web/$domain/nodeapp"

mkdir $nodeDir
chown -R $user:$user $nodeDir

nodeVersion=""
nvmDir="/opt/nvm"
nodePath=""
packageManager=""
envFile=""

#if are installed .nvm on the system
if [ -d "$nvmDir" ]; then
    
    #check files .naverc .node-version .nvm
    if [ -f "$nodeDir/.nvm" ]; then
        nodeVersion=$(cat $nodeDir/.nvm)
    elif [ -f "$nodeDir/.node-version" ]; then
        nodeVersion=$(cat $nodeDir/.node-version)
    fi

    echo "Needs Node version: $nodeVersion"

    export NVM_DIR="/opt/nvm/"
    source "$NVM_DIR/nvm.sh"

    if [ ! -d "/opt/nvm/versions/node/$nodeVersion" ]; then
        echo "Install this version"
        nvm install $nodeVersion

        chmod -R 777 /opt/nvm
    else
        echo "Error on install Node version on NVM"
    fi

    nodePath="/opt/nvm/versions/node/$nodeVersion/bin/node"
    packageManager="/opt/nvm/versions/node/$nodeVersion/bin/npm"
fi

package_manager=""
start_script=""

if [ -f $nodeDir/.package_manager.rc ]; then
    package_manager=$(cut $nodeDir/.package_manager.rc)
fi

if [ -f $nodeDir/.start_script.rc ]; then
    start_script=$(cut $nodeDir/.start_script.rc)
fi

# check available package manager
if [ $package_manager ]; then
    packageManager="/opt/nvm/versions/node/$nodeVersion/bin/$package_manager"
fi

# check available start script
if [ $start_script ]; then
    mainScript="$start_script"
fi

#auto install dependences
if [ ! -d "$nodeDir/node_modules" ]; then
    echo "No modules found. Installing now"
    cd $nodeDir && eval "$packageManager install"
else
    echo "modules found, removing and reinstalling now"
    cd $nodeDir
    rm -rf "node_modules"
    eval "$packageManager install"
fi

#get init script form package.json
package="$nodeDir/package.json"

if [ -e $package ]
then
    scriptName=$(cat $package \
                | grep name \
                | head -1 \
                | awk -F: '{ print $2 }' \
                | sed 's/[",]//g' \
                | sed 's/ *$//g')
fi

rm "$nodeDir/app.sock"
runuser -l $user -c "pm2 del $scriptName"

#apply enviroment variables from .env file
if [ -f "$nodeDir/.env" ]; then
    echo ".env file in folder, applying."
    envFile=$(grep -v '^#' $nodeDir/.env | xargs | sed "s/(PORT=(.*) )//g")
    echo $envFile
else
    echo ".env file not in folder creating and applying"
    touch "$nodeDir/.env"
    envFile=$(grep -v '^#' $nodeDir/.env | xargs | sed "s/(PORT=(.*) )//g")
    echo $envFile
fi

#remove blank spaces
pmPath=$(echo "$mainScript" | tr -d ' ')
runuser -l $user -c "$envFile PORT=$nodeDir/app.sock HOST=127.0.0.1 PWD=$nodeDir NODE_ENV=production pm2 start \"$packageManager $mainScript\" --name $scriptName"

echo "Waiting for init PM2"
sleep 5

if [ ! -f "$nodeDir/app.sock" ]; then
    echo "Allow nginx access to the socket $nodeDir/app.sock"
    chmod 777 "$nodeDir/app.sock"
else
    echo "Sock file not present disable Node app"
    runuser -l $user -c "pm2 del $scriptName"
    rm $nodeDir/app.sock
fi

#copy pm2 logs to app folder
echo "Copy logs to nodeapp folder"
cp -r $home/$user/.pm2/logs/$domain-error.log $nodeDir
cp -r $home/$user/.pm2/logs/$domain-out.log $nodeDir