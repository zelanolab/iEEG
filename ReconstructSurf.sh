#!/usr/bin/env bash
#
# Freesurfer cortical reconstruction
# Required Files: T1.nii.gz in directory wkpath-to-file
#   ./ReconstructSurf.sh  full-path-to-file/T1.nii.gz
#
#  If you have a skull-stipped brain you want to use, put it in the same folder as T1.nii.gz and name it as T1_brain.nii.gz
#   ./ReconstructSurf.sh  full-path-to-file/T1.nii.gz T1_brain
#
#   In this case, you can also change the subject_id (default FS)
#   ./ReconstructSurf.sh  full-path-to-file/T1.nii.gz T1_brain FSAlso
#   

#export FREESURFER_HOME=/Applications/freesurfer/7.2.0
#source $FREESURFER_HOME/SetUpFreeSurfer.sh

if [[ "$#" -lt 1 ]]; then
    printf "Not enough input arguments.\n"
    exit 1
fi

# full-path-to-mri (including extension)
# e.g. ~/Desktop/MR.nii.gz
mri=$1

# brain file name, in the same directory of mri
# e.g. MR_brain
brain=$2

if [[ "$#" -lt 3 ]]; then
    subjid=FS
else
    subjid=$3
fi

subjdir=$( dirname ${mri})
export SUBJECTS_DIR=${subjdir}

mridir=$SUBJECTS_DIR/${subjid}/mri
labeldir=$SUBJECTS_DIR/${subjid}/label

rerun=0
orig_path=$(pwd)


if [[ -f ${labeldir}/rh.aparc.a2009s.annot && $rerun -ne 0 ]]; then
    printf "Cortical reconstruction has been run, skipped.\n"
    exit 0
fi

recon-all -i ${mri} -subjid ${subjid} -no-isrunning
recon-all -autorecon1 -subjid ${subjid} -no-isrunning

cd "${mridir}"

# replace auto-brain with skull-stripped brainmask
if [[ ${brain} != "" ]]; then
    brain=$( ${FSLDIR}/bin/remove_ext ${brain})

    #First, create a registration matrix between the conformed space (orig.mgz) and the native anatomical (rawavg.mgz)
    tkregister2 --mov rawavg.mgz --targ orig.mgz --reg register.native.dat --noedit --regheader
    mri_vol2vol --mov ${brain}.nii.gz --targ T1.mgz --reg register.native.dat --o ${brain}2FS.mgz
    mri_convert ${brain}2FS.mgz ${brain}2FS.nii.gz
    mri_convert T1.mgz T1.nii.gz
    fslmaths ${brain}2FS.nii.gz -bin -mul T1.nii.gz T1_mul_${brain}.nii.gz
    mri_convert T1_mul_${brain}.nii.gz T1_mul_${brain}.mgz
    cp T1_mul_${brain}.mgz brainmask.auto.mgz
    cp brainmask.auto.mgz /brainmask.mgz
fi

#** check skull strip result
# freeview -v ${subjdir}/${subjid}/mri/T1.mgz ${subjdir}/${subjid}/mri/brainmask.mgz
# continue with the reconstruction, this step takes a long time < 20 hrs
recon-all -autorecon2 -subjid ${subjid} -no-isrunning
recon-all -autorecon3 -subjid ${subjid} -no-isrunning
recon-all -s ${subjid} -qcache -no-isrunning

# Freesurfer hippocampus and amygdala segmentation
command -v ${FREESURFER_HOME}/bin/segmentHA_T1.sh 1>/dev/null
[ $? -eq 0 ] && ${FREESURFER_HOME}/bin/segmentHA_T1.sh ${subjid}

## smooth surface for electrodes projection
current_dir=$(pwd)
scriptdir=$(dirname '$0')
[ '$scriptdir' == '.' ] && scriptdir="$current_dir"
file=${scriptdir}/ReconstructSurf_PrepareProj.sh
if [[ -f ${file} ]]; then
    chmod +x ${file}
    ${file} ${subjdir}/${subjid}/surf
fi

cd "${orig_path}"
