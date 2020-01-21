#!/usr/bin/perl -w
#===============================================================================
#
#        Li Xue (), me.lixue@gmail.com
#        12/11/2015 10:44:01 AM
#
#  DESCRIPTION: For one decoy file,  calculate potentials between two atoms: Evdw and Eelec
#
#
#       INPUT (decoy pdb file):
#
#       OUTPUT:
#       atom-atom contact pair; dist; Eelec_interchain; Evdw_interchain
#
#
#  NOTE:
#  1. E0 is 10 in it0 and it1 and 1 in water for the electrostatic term
#  2. ligand.top is generated by PRODRG
#===============================================================================

use strict;
use warnings;
use utf8;
use Math::Trig;
use File::Basename;


#----- input
my $commandline = $0 . "  ". (join "  ", @ARGV);

my $pdbFL = shift @ARGV;
our $cutoff = shift @ARGV;  # haddock uses 8.5
my $topfile_DIR = shift @ARGV; #'top_files';
our $e0 =shift @ARGV; # #-- NOTE: E0 is 10 in it0 and it1 and 1 in water for the electrostatic term

if (!defined $e0){
    print"\n\tUsage: perl potentialAtome_oneDecoy.pl pdbFL(with_segID) contact_distance_cutoff topfile_DIR E0\n\n";
    print "\tNOTE: E0 is 10 in it0 and it1 and 1 in water for the electrostatic term.\n";
    print "\tNOTE: contact_distance_cutoff: haddock uses 8.5 A\n\n";
    exit;
}

#--------------------------------------#
#--------- parameter files  -----------#

our $paramFL_aa =
  "$topfile_DIR/protein-allhdg5-4_new.param";
our $topFL_aa =
  "$topfile_DIR/protein-allhdg5-4_new.top";

our $aa_typeFL = "$topfile_DIR/aa_types.txt"
  ;    # the list of aa types that haddock supports

our $topFL_patch = "$topfile_DIR/patch.top"
  ;    #change the type and charge of some atoms

my $patchTypeDIR = "$topfile_DIR";


print "\n\nE0=$e0 (NOTE: E0 is 10 in it0 and it1 and 1 in water for the electrostatic term)\n\n";


if (!-e $topFL_aa){
    die("$topFL_aa does not exist:$!");
}


#---- ligand top file and param file

our $paramFL_ligand =
  "$topfile_DIR/ligand.param";

our $topFL_ligand_ori =
  "$topfile_DIR/ligand.top";
our $topFL_ligand = "$topfile_DIR/ligand.top_modified";
system("./modify_top.pl $topFL_ligand_ori > $topFL_ligand") ==0 or die ("Cannot reformat ligand.top:$!");



#-------program starts --------------------
print "# generated by $commandline \n";
print "# interface threshold: $cutoff\n";
print "# residue1\tchnID1\tatomResNum1\tatomName1\tatomNum1\tresidue2\tchnID2\tatomResNum2\tatomName2\tatomNum2\tdist\tEelec\tEvdw\n";


#-- read supported aa types
our $aa_types = &read_aaTypeFL($aa_typeFL);

#--read parameter and topology files

our ( $params_interchain_aa, $params_intrachain_aa ) =
  &read_paramFL($paramFL_aa);
our ( $AtomTypes_aa, $AtomCharges_aa ) = &read_topFL($topFL_aa);

our ( $params_interchain_ligand, $params_intrachain_ligand ) =
  &read_paramFL($paramFL_ligand);
our ( $AtomTypes_ligand, $AtomCharges_ligand ) = &read_topFL($topFL_ligand);

our $patch = &read_patchFL($topFL_patch);

#- $patch->{CTER}->{CA}->{charge}=0.1;
#- $patch->{CTER}->{CA}->{type}=HC

#-- determine residue patch type (Cter, Nter, HISE, and so on)
my $basename = basename( $pdbFL, '.pdb' );
my $patchTypeFL = "$patchTypeDIR/$basename.patchType";
system("perl preScan.pl $pdbFL > $patchTypeFL") == 0
  or die("Failed: preScan.pl:$!");
my $patchTypes = &read_patchTypeFL($patchTypeFL);

#- $patchTypes->{chnID}->{atomResNum}='CTER'

#-- calculate atom-atom contact pairs and their distances
my $rand = int(rand(100));
my $outDIR_tmp = "/tmp/$rand";
system("bash get_contactResiPairs.sh $pdbFL $cutoff $outDIR_tmp ") == 0
  or die("Failed: get_contactResiPairs.sh $pdbFL:$!");
my $atomContactFL = "$outDIR_tmp/$basename.atomContact";    #this is one of the output files from get_contactResiPairs.sh

#-- calculate potentials
my $Eelec_sum = 0;
my $Evdw_sum  = 0;

open( INPUT, "<$atomContactFL" ) or die("Cannot open $atomContactFL:$!");
while (<INPUT>) {
    s/[\n\r]//mg;

    if (/^\w{3}\s+/) {

        #MET	A	   5 	 CG 	 2760	ALA	C	   1 	 HN 	 2760	4.66823971

        #print "\natom-atom contact pair: $_\n";
        my $line = $_;
        check_contactFL_format($line);

        my (
            $residue1, $chnID1,      $atomResNum1, $atomName1, $atomNum1,
            $residue2, $chnID2,   $atomResNum2, $atomName2,   $atomNum2, $dist
        ) = split( /\s+/, $line);

        #-- determine paramters for each atom
        my $patchType1 = $patchTypes->{$chnID1}->{$atomResNum1};    # 'CTER'
        my ( $e1, $sigma1, $charge1, $atomType1 ) =
          &getParameters_interchain( $residue1, $atomName1, $patchType1 );

          if (! defined $atomType1){
              die("atom1's chemical type not defined:$!");
          }

#          print "First atom: patchType = $patchType1; atom_chemical_Type = $atomType1; charge = $charge1\n";

        my $patchType2 = $patchTypes->{$chnID2}->{$atomResNum2};    # 'CTER'
        my ( $e2, $sigma2, $charge2, $atomType2 ) =
          &getParameters_interchain( $residue2, $atomName2, $patchType2 );

#          print "Second atom: patchType = $patchType2; atom_chemical_Type = $atomType2; charge = $charge2\n";

        #--Evdw_interchain

        my $Evdw_interchain = 0;
#        if ( !&is_H($atomName1) && !&is_H($atomName2) ) {

            #-- only non-H atoms are considered for Evdw
            $Evdw_interchain =
              &vdw_oneAtomPair( $e1, $sigma1, $e2, $sigma2, $dist );
#        }
#        else {
#            print "Evdw is not calculated for hydrogen atoms\n";
#        }

        #--Eelec
        my $Eelec = &elec_oneAtomPair( $charge1, $charge2, $dist );

        print "$line\t$Eelec\t$Evdw_interchain\n";

        #--
        $Evdw_sum  = $Evdw_sum + $Evdw_interchain;
        $Eelec_sum = $Eelec_sum + $Eelec;
    }

}
close INPUT;

print "\n\n#Total Evdw = $Evdw_sum\n";
print "#Total Eelec = $Eelec_sum\n";

#- clean up: delete the modifed ligand.top file
unlink ($topFL_ligand) if (-e $topFL_ligand);


#-----------------------------

sub read_aaTypeFL {
    my $lstFL = shift @_;
    my %aa_types;
    my @a = `cat $lstFL`;

    if ( scalar @a == 0 ) {
        die("nothing read from $lstFL:$!");

    }
    my @a_final;

    foreach (@a) {
        s/[\n\r]//mg;
        s/\s+//mg;
        $aa_types{$_} = 1;
    }

    return \%aa_types;
}

sub getParameters_interchain {
#
#-- determine a residue is an aa or cofactor first, then assign parameters to the atom
#-- also, adjust the parameters based on the residue's patch type (i.e., CTER, NTER, HISE, and so on)

    use strict;
    our  $params_interchain_aa;
    our ( $AtomTypes_aa,         $AtomCharges_aa );

    our  $params_interchain_ligand;
    our ( $AtomTypes_ligand,         $AtomCharges_ligand );

    our $patch;

    #- $patch->{CTER}->{CA}->{charge}=0.1;

    #-----

    my ( $residue, $atomName, $patch_type ) = @_;

    my ( $e, $sigma, $charge, $atomType );
    if ( &is_aa($residue) ) {

        #        print "$residue is amino acid\n";

        #        $atomType = $AtomTypes_aa->{$residue}->{$atomName};

        ( $e, $sigma, $charge, $atomType ) =
          &assignParam( $residue, $atomName, $AtomTypes_aa, $AtomCharges_aa,
            $params_interchain_aa, $topFL_aa, $paramFL_aa );

        if ( $patch_type !~ /Nan/i ) {

#-- if $residue is at the terminus or other special situation, adjust the parameters
#            print "warning: patch_type ( $patch_type ) is not nan. Adjust parameters for this atom\n";
            ( $e, $sigma, $charge, $atomType ) =
              &adjust( $e, $sigma, $charge, $atomType, $patch_type, $params_interchain_aa,
                $atomName );

        }
    }

    else {
        ( $e, $sigma, $charge, $atomType ) =
          &assignParam( $residue, $atomName, $AtomTypes_ligand,
            $AtomCharges_ligand,
            $params_interchain_ligand, $topFL_ligand, $paramFL_ligand );
    }

    #----
    if ( !defined $e || !defined $sigma || !defined $charge || !defined $atomType) {
        die(
"e, sigma, charge and/or atom chemical tpye for atom $atomName of residue $residue (patch type: $patch_type) are not assigned. Check parameter files:$!"
        );
    }

    return ( $e, $sigma, $charge, $atomType );
}

sub adjust {

    #----- if the residue is at the N-ter or C-ter
    # Some atoms are at the C-ter or N-ter patch (see *.top file)

    our $topFL_patch;
    our $patch;
    our $paramFL;

    #- $patch->{CTER}->{CA}->{charge}=0.1;

    #--
    my ( $e_ori, $sigma_ori, $charge_ori,$atomType_ori, $patch_type, $params, $atomName ) =
      @_;
    my ( $e_new, $sigma_new, $charge_new , $atomType_new);

    #--
    if ( !defined $patch->{$patch_type} ) {
        die("Patch type $patch_type not defined in $topFL_patch:$!");
    }

    if ( !defined $patch->{$patch_type}->{$atomName} ) {
        print
"#warning: atom $atomName (patch type $patch_type) not defined in $topFL_patch. No parameter changed.\n";
        $e_new      = $e_ori;
        $sigma_new  = $sigma_ori;
        $charge_new = $charge_ori;
        $atomType_new = $atomType_ori;
        return ( $e_new, $sigma_new, $charge_new ,$atomType_new);
    }

    if ( !defined $patch->{$patch_type}->{$atomName}->{'CHARGE'} ) {
        $charge_new = $charge_ori;
    }
    else {
        $charge_new = $patch->{$patch_type}->{$atomName}->{'CHARGE'};
    }

    if ( !defined $patch->{$patch_type}->{$atomName}->{'TYPE'} ) {
        $atomType_new = $atomType_ori;

        #-- atom chemical type determines the $e and $sigma
        $e_new     = $e_ori; #eps: a parameter used in L-J function
        $sigma_new = $sigma_ori;
    }
    else {

         $atomType_new = $patch->{$patch_type}->{$atomName}->{'TYPE'};
        ( $e_new, $sigma_new ) = @{ $params->{$atomType_new} };

        if (   !defined $sigma_new
            || !defined $e_new )
        {
            die(
"atom $atomType_new does not have sigma and/or e defined in $paramFL:$!"
            );
        }

    }

    return ( $e_new, $sigma_new, $charge_new ,$atomType_new);
}

#sub adjustTermi{
#        #----- if the residue is at the N-ter or C-ter
#        # Some atoms are at the C-ter or N-ter patch (see *.top file)
#
#        my ($e, $sigma, $charge, $atomName, $AtomTypes_aa, $params_interchain_aa) = @_;
#
#        if (&is_Nter($residue)){
#            # may modify, delete $e, $sigma, and/or $charge
#            ($e, $sigma, $charge, $action) = &assignParam_terminal ($atomName, $e, $sigma, $charge, 'Nter');
#        }
#
#        elsif (&is_Cter($residue)){
#            ($e, $sigma, $charge) = &assignParam_terminal ($atomName, $e, $sigma, $charge, 'Cter');
#        }
#        return ($e, $sigma, $charge);
#
#}

sub is_aa {
    our $aa_types;

    my $residue_name = shift @_;
    my $ans;

    $ans = $aa_types->{$residue_name};

    if ( !defined $ans ) {
        $ans = 0;
    }
    return $ans;
}

sub assignParam {
    use strict;
    my ( $aa, $atomName, $AtomTypes, $AtomCharges, $params, $topFL, $paramFL )
      = @_;

    my $atomType = $AtomTypes->{$aa}->{$atomName};

    if ( !defined $atomType ) {

#        print
#"\n: warning: atoms $atomName in residue $aa do not have defined atom types in $topFL. It might be defined in patch.top !!!\n\n";
        return;
    }

    if (!defined $params->{$atomType}){

        die(
            "parameters for atom $atomType is not defined in $topFL or $paramFL:$!"
        );
    }

    my ( $e, $sigma ) = @{ $params->{$atomType} };

    if (   !defined $sigma
        || !defined $e )
    {
        die(
            "atom $atomType does not have sigma and/or e defined in $paramFL:$!"
        );
    }

    my $charge = $AtomCharges->{$aa}->{$atomName};

    if ( !defined $charge ) {
        die("atom $atomName does not have charge defined in $topFL:$!");
    }
    return ( $e, $sigma, $charge, $atomType );

}

#sub vdw_oneAtomPair_interchain {
#    my ( $atomName1, $atomName2, $dist, $params_interchain, $AtomTypes, $topFL,
#        $paramFL )
#      = @_;
#
#    my $atomType1 = $AtomTypes->{$atomName1};
#    my $atomType2 = $AtomTypes->{$atomName2};
#
#    if ( !defined $atomType1 || !defined $atomType2 ) {
#        die(
#"atoms $atomName1 or $atomName2 do not have defined atom types in $topFL:$!"
#        );
#    }
#
#    my ( $e1, $sigma1 ) = @{ $params_interchain->{$atomType1} };
#    my ( $e2, $sigma2 ) = @{ $params_interchain->{$atomType2} };
#
#    if (   !defined $sigma1
#        || !defined $sigma2
#        || !defined $e1
#        || !defined $e2 )
#    {
#        die(
#"atom $atomType1 or $atomType2 do not have sigma and/or e defined in $paramFL:$!"
#        );
#    }
#
#    my $Evdw = &vdw_oneAtomPair( $e1, $sigma1, $e2, $sigma2, $dist );
#    return $Evdw;
#}

sub elec_oneAtomPair {

    #-- see Alex's email for this equation
    #-- NOTE: E0 is 10 in it0 and it1 and 1 in water for the electrostatic term

    #our $cutoff;
    my $R_off = 8.5;
    our $e0 ; #-- NOTE: E0 is 10 in it0 and it1 and 1 in water for the electrostatic term
    my $C = 332.0636;

    #--
    my $Eelec;
    my ( $q1, $q2, $R ) = @_;
    #    my $Eelec = 1 / ( 4 * pi * $e0 ) * $q1 * $q2 / $R;
    if ( $R < $R_off ) {
        $Eelec = $q1 * $q2 * $C / ( $e0 * $R ) * ( 1 - $R**2 / $R_off**2 )**2;
    }
    else {
        $Eelec = 0
    }

    if ( $Eelec == 0 ) {
        $Eelec = 0
    }

    return $Eelec;
}

sub elec_oneAtomPair_WRONG {

    #-- see Alex's email for this equation
    #-- NOTE: E0 is 10 in it0 and it1 and 1 in water for the electrostatic term

    our $cutoff;
    our $e0 ; #-- NOTE: E0 is 10 in it0 and it1 and 1 in water for the electrostatic term
    my $C = 332.0636;

    #--
    my ( $q1, $q2, $R ) = @_;

    #    my $Eelec = 1 / ( 4 * pi * $e0 ) * $q1 * $q2 / $R;
    my $Eelec = $q1 * $q2 * $C / ( $e0 * $R ) * ( 1 - $R**2 / $cutoff**2 )**2;

    return $Eelec;
}

#sub vdw_oneAtomPair {
#    my ( $e1, $sigma1, $e2, $sigma2, $R ) = @_;
#
#    #-- sigma
#    my $sigma = ( $sigma1 + $sigma2 ) / 2;
#
#    #-- e
#    my $e = sqrt( $e1 * $e2 );
#
#    #--
#    my $Evdw = 4 * $e * ( ( $sigma / $R )**12 - ( $sigma / $R )**6 );
#
#    return $Evdw;
#
#}

sub vdw_oneAtomPair {

    #see Alex's email for this equation
    #
    my ( $e1, $sigma1, $e2, $sigma2, $R ) = @_;

#    $e1     = 0.0903;
#    $sigma1 = 3.3409;
#    $e2     = 0.12;
#    $sigma2 = 3.3409;
#    $R      = 8.363386;

    #-- sigma
    my $sigma = ( $sigma1 + $sigma2 ) / 2;

    #-- e
    my $e = sqrt( $e1 * $e2 );

    #--
    my $sw_R = &sw_R($R);

    #$sw_R =1;
    my $Evdw = 4 * $e * ( ( $sigma / $R )**12 - ( $sigma / $R )**6 ) * $sw_R;

#    print
#"eps1=$e1; eps2=$e2; eps=sqrt(eps1*eps2)=$e; sigma1= $sigma1; sigma2= $sigma2; sigma = (sigma1 + sigma2)/2 = $sigma; sw(R)= $sw_R; Evdw = $Evdw\n";

    if ( $Evdw == 0 ) {
    # to remove the case $Evdw = -0
        $Evdw = 0
    }
    return $Evdw;

}

sub sw_R {
    my $r = shift @_;
    my $sw_R;
    my $R_off = 8.5;
    my $R_on  = 6.5;

    if ( $r > $R_off ) {
        $sw_R = 0;
    }
    elsif ( $r < $R_on ) {
        $sw_R = 1;
    }
    else {
        $sw_R =
          ( $R_off**2 - $r**2 )**2 *
          ( $R_off**2 - $r**2 - 3 * ( $R_on**2 - $r**2 ) ) /
          ( $R_off**2 - $R_on**2 )**3;
    }
    return $sw_R;

}

sub read_paramFL {

#    NONBONDED  CHAI  0.10000 3.29633 0.10000 3.02906
#    NONBONDED  CHAO  0.10000 3.29633 0.10000 3.02906
#
#There are four columns of numbers.
#The first two are for inter-chain interactions
#The last two are for intra-chain interactions between atoms separated by <= four bonds

    my $paramFL = shift @_;
    my $params_interchain;
    my $params_intrachain;

    open( INPUT, "<$paramFL" ) or die("Cannot open $paramFL:$!");
    while (<INPUT>) {
        s/[\n\r]//mg;

        if (/^nonbonded/i )
          {
              my ( $tmp, $atomType, $e, $sigma, $e2, $sigma2 ) =
                split( /\s+/, $_ );

              my @pair_inter = ( $e,  $sigma );
              my @pair_intra = ( $e2, $sigma2 );
              $params_interchain->{$atomType} = \@pair_inter;
              $params_intrachain->{$atomType} = \@pair_intra;

        }
    }
    close INPUT;

    if ( !defined $params_intrachain || !defined $params_interchain ) {
          print("#warning: Nothing read from $paramFL\n");
    }
    return ( $params_interchain, $params_intrachain );
}

sub read_topFL {

      # read topology file
      #
      #ACE    atom HA3 type=HA charge= 0.000 end
      #ACE    atom C   type=C  charge= 0.500 end

      my $topFL = shift @_;
      my $AtomTypes;
      my $AtomCharges;
      my $flag =1; #1: the $topFL format is wrong

      open( INPUT, "<$topFL" ) or die("Cannot open $topFL:$!");
      while (<INPUT>) {
          s/[\n\r]//mg;

          if (/^\w{3}\s+atom\s+.+\s+type=.+\s+charge=.+/i){
          #ACE    atom HA3 type=HA charge= 0.000 end
          #MLY    atom CE   type=CH2E  charge=-0.154 end
          #CYF    atom CB  type=CH2E   charge=-0.020 end ! charged AB for better Zn coordination
          #ILE    atom HG11 type=HA      charge= 0.000 excl = (HG21 HG22 HG23 HD11 HD12 HD13) end

#            my ( $aa, $tmp, $atomName, $tmp2, $Type, $tmp3, $charge ) =
#                split( /[\s+=]+/, $_ );

          $flag = 0;

            s/=/ /g;
            my @tmp = split( /\s+/, $_ );
            my $aa = $tmp[0];
            my $atomName = $tmp[2];
            my $Type = $tmp[4];
            my $charge = $tmp[6];

            if ( !defined $Type ) {
                print "\nError reading top file ( $topFL) :\n";
                print "Line: $_\n";
                die("type $Type not defined:$!");
            }

            #        if ( $aa eq 'TRP' ) {
            #
            #            print
            #"aa=$aa; atomName = $atomName; atomType = $Type; charge = $charge\n";
            #        }
            $AtomTypes->{$aa}->{$atomName}   = $Type;
            $AtomCharges->{$aa}->{$atomName} = $charge;

          }
      }
      close INPUT;


      if ($flag == 1){
          warn ("WARNING: topology file ($topFL) is empty or the format is wrong!\n");
      }

      return ( $AtomTypes, $AtomCharges );
}

sub read_patchFL {

      #- $patch->{CTER}->{CA}->{charge}=0.1;
      #- $patch->{CTER}->{CA}->{type}=HC

      #input:
      #   CYNH    MODIFY    ATOM 1CB              CHARGE= 0.000
      #   CYNH    MODIFY    ATOM 1SG  TYPE=S      CHARGE=-0.500
      #
      my $patchFL = shift @_;
      my $patch;

      open( INPUT, "<$patchFL" ) or die("Cannot open $patchFL:$!");
      while (<INPUT>) {
          s/[\n\r]//mg;

          if (/^\w+/) {

              #    NTER    add       atom +HT1 type=HC  charge= 0.330 end
              my @a         = split( /\s+/, $_ );
              my $patchType = shift @a;             #  $a[0];
              my $action    = shift @a;             # $a[1];
              shift @a;
              my $atomName = shift @a;              #$[3];

              foreach my $tmp (@a) {

                  #$tmp = 'type=S'
                  #$tmp = 'charge=0.000'
                  my ( $name, $value ) = split( /=/, $tmp );

                  if ( !defined $value ) {
                      print "line: $_; tmp:$tmp; name: $name; \n";
                      die("value not defined:$!");
                  }
                  $patch->{$patchType}->{$atomName}->{$name} = $value;
              }

          }
      }
      close INPUT;

      if ( !defined $patch ) {
          die("Nothing read from $patchFL:$!");
      }

      return $patch;

}

sub read_patchTypeFL {

      #    A   123 HIS HISE
      #    A   124 ASN Nan

      my $patchTypeFL = shift @_;
      my $patchTypes;

      open( INPUT, "<$patchTypeFL" ) or die("Cannot open $patchTypeFL:$!");
      while (<INPUT>) {
          s/[\n\r]//mg;

          if (/^\w{1}\s+/) {
              my ( $chainID, $atomResnum, $aa, $patch_type ) =
                split( /\s+/, $_ );
              $patchTypes->{$chainID}->{$atomResnum} = $patch_type;

          }
      }
      close INPUT;

      if ( !defined $patchTypes ) {
          die("Nothing read from $patchTypeFL:$!");
      }
      return $patchTypes;

}

sub is_H {
      my $atomName = shift @_;
      my $ans      = 0;

      if ( substr( $atomName, 0, 1 ) eq 'H' ) {
          $ans = 1;

      }
      return $ans;
}
sub check_contactFL_format{
        my $line = shift @_;
        my @tmp = split(/\s+/, $line);
        my $num_column = scalar(@tmp);
        if (scalar(@tmp) ne 11){
            die("$atomContactFL has $num_column columns (expecting 11). Check its format:$!")
        }
}
