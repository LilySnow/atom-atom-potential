# Output 1 (contact residue-residue file):
#   ILE    A   196 THR B   198 8.021
#   ASN    B   162 2BA A   301 5.844
#
# Output 2 (contact atom-atom file):
#   THR A    143     N      ARG B    173     NH2    8.40174518
#   THR A    143     CA     ARG B    173     NH2    7.92224059

set -e

decoyFL=$1
anyAtomDistThr=$2; #8.5
outputDIR=$3

if [ ! -d $outputDIR ];then
    mkdir -p $outputDIR
fi

#-- get rid of .pdb
#FLname=`echo $decoyFL |sed 's/.pdb$//'`

#--
FLname=`basename $decoyFL ".pdb"`
outFL1=$outputDIR/$FLname.atomContact
outFL2=$outputDIR/$FLname.resiContact

#-- get the contact residue list
pdb_segxchain.py $decoyFL > $outputDIR/$FLname.new
contact-chainID_allAtoms $outputDIR/$FLname.new $anyAtomDistThr  > $outFL1
removeAtomFromContactFL $outFL1 > $outFL2

#-- filter out water from the residue-residue contact file: HOH, WAT
egrep -v 'HOH' $outFL2 | egrep -v 'WAT' > $outFL2.tmp
mv $outFL2.tmp $outFL2

#-- clean up
unlink $outputDIR/$FLname.new

#echo "$outputDIR/$FLname.atomContact generated"
#echo "$outputDIR/$FLname.resiContact generated"

#--

