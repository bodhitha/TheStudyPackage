#!/bin/bash
#===================================================================================================
#
# Execute one job on the grid or interactively.
#
#===================================================================================================
# make sure we are locked and loaded
[ -d "./bin" ] || ( tar fzx default.tgz )
export BASEDIR=`pwd`
source ./bin/helpers.sh
setupProxy

# command line arguments
TASK="$1"
GPACK="$2"

# load all parameters relevant to this task
echo " Initialize package"
source $BASEDIR/config/${TASK}.env

# make sure to contain file mess
mkdir ./work
cd    ./work
export WORKDIR=`pwd`

# tell us the initial state
initialState $*

# make a working area
echo " Start to work now"
pwd
ls -lhrt

# initialize LHE/GEN step
setupCmssw $GEN_CMSSW_VERSION $GEN_PY
export PYTHONPATH="${PYTHONPATH}:$BASEDIR/python"

# start clean by removing copies of existing generator
executeCmd rm -rf $GENERATOR

# get our fresh generator tar ball
executeCmd tar fzx $BASEDIR/generators/$GENERATOR.tgz

####################################################################################################
# C H O O S E   T H E   G E N E R A T O R  [and run it]
####################################################################################################
echo " INFO -- using generator type: $GENERATOR_TYPE"
if [ "$GENERATOR_TYPE" == "powheg" ]
then
  executeCmd time $BASEDIR/bin/runPowheg.sh $TASK $GPACK
elif [ "$GENERATOR_TYPE" == "madgraph" ]
then
  executeCmd time $BASEDIR/bin/runMadgraph.sh $TASK $GPACK
else
  echo " ERROR -- generator type is not known (\$GENERATOR_TYPE=$GENERATOR_TYPE)"
  echo "          EXIT now because there is no LHE file."
  exit 1
fi

####################################################################################################
# hadronize step
####################################################################################################

cd $WORKDIR
pwd
ls -lhrt

# already done
echo " Initialize CMSSW for Gen - $GEN_CMSSW_VERSION -> $GEN_PY"

# prepare the python config from the given templates
cat $BASEDIR/python/${GEN_PY}.py-template \
    | sed "s@XX-HADRONIZER-XX@$HADRONIZER@g" \
    | sed "s@XX-FILE_TRUNC-XX@${TASK}_${GPACK}@g" \
    > ${GEN_PY}.py

executeCmd time cmsRun ${GEN_PY}.py

####################################################################################################
# fastsim step
####################################################################################################

cd $WORKDIR
pwd
ls -lhrt

# initialize FASTSIM step
setupCmssw $SIM_CMSSW_VERSION $SIM_PY

# prepare the python config from the given templates
cat $BASEDIR/python/${SIM_PY}.py-template \
    | sed "s@XX-HADRONIZER-XX@$HADRONIZER@g" \
    | sed "s@XX-FILE_TRUNC-XX@${TASK}_${GPACK}@g" \
    > ${SIM_PY}.py

executeCmd time cmsRun ${SIM_PY}.py

####################################################################################################
# miniaod step
####################################################################################################

cd $WORKDIR
pwd
ls -lhrt

# initialize MINIAOD step
setupCmssw $MIN_CMSSW_VERSION $MIN_PY

# prepare the python config from the given templates
cat $BASEDIR/python/${MIN_PY}.py-template \
    | sed "s@XX-HADRONIZER-XX@$HADRONIZER@g" \
    | sed "s@XX-FILE_TRUNC-XX@${TASK}_${GPACK}@g" \
    > ${MIN_PY}.py

executeCmd time cmsRun ${MIN_PY}.py

# bambu step

cd $WORKDIR
pwd
ls -lhrt

####################################################################################################
# initialize BAMBU
####################################################################################################
setupCmssw $BAM_CMSSW_VERSION $BAM_PY
export PYTHONPATH="${PYTHONPATH}:$BASEDIR/python"

# unpack the tar
cd CMSSW_$BAM_CMSSW_VERSION
executeCmd time tar fzx $BASEDIR/tgz/bambu043.tgz
cd $WORKDIR

# prepare the python config from the given templates
cat $BASEDIR/python/${BAM_PY}.py-template \
    | sed "s@XX-HADRONIZER-XX@$HADRONIZER@g" \
    | sed "s@XX-FILE_TRUNC-XX@${TASK}_${GPACK}@g" \
    > ${BAM_PY}.py

executeCmd time cmsRun ${BAM_PY}.py
# this is a little naming issue that has to be fixed
mv ${TASK}_${GPACK}_bambu*  ${TASK}_${GPACK}_bambu.root

####################################################################################################
# push our files out to the Tier-2
####################################################################################################
cd $WORKDIR
# define base output location
REMOTE_SERVER="se01.cmsaf.mit.edu"
REMOTE_BASE="srm/v2/server?SFN=/mnt/hadoop/cms/store"
REMOTE_USER_DIR="/user/paus/study"

# this is somewhat overkill but works very reliably, I suppose
setupCmssw 7_6_3 cmscp.py
tar fzx $BASEDIR/tgz/copy.tgz
pwd=`pwd`
for file in `echo ${TASK}_${GPACK}*`
do
  # always first show the proxy
  voms-proxy-info -all
  # now do the copy
  executeCmd time ./cmscp.py \
    --debug --middleware OSG --PNN $REMOTE_SERVER --se_name $REMOTE_SERVER \
    --inputFileList $pwd/${file} \
    --destination srm://$REMOTE_SERVER:8443/${REMOTE_BASE}${REMOTE_USER_DIR}/${TASK} \
    --for_lfn ${REMOTE_USER_DIR}/${TASK}
done

exit 0


## pwd=`pwd` # just to make sure it is the full directory
## for file in `echo ${TASK}_${GPACK}*`
## do
## 
## 
##   executeCmd time \
##     lcg-cp -D srmv2 -b file://$pwd/$file \
##            srm://$REMOTE_SERVER:8443/${REMOTE_BASE}${REMOTE_USER_DIR}/${TASK}/$file
## done

