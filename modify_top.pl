#!/usr/bin/perl -w
#===============================================================================
#
#        Li Xue (), me.lixue@gmail.com
#        12/10/2015 03:40:28 PM
#
#  DESCRIPTION: Extract atom charge information from /home/software/haddock/haddock2.2/toppar/protein-allhdg5-4.top
#        INPUT:
#       OUTPUT:
#
#        USAGE: ./modify_top.pl
#
#        NOTES: ---
#===============================================================================

use strict;
use warnings;
use utf8;

my $topFL = shift @ARGV; #'/home/software/haddock/haddock2.2/toppar/protein-allhdg5-4.top';

my $flag_residue = 0;
my $residue_type ;
my $num_type =0;

print "#generated by $0 $topFL\n";
open (INPUT, "<$topFL") or die ("Cannot open $topFL:$!");
while(<INPUT>){
    s/[\n\r]//mg;

    if (/^residue\s+(\w+)/i){
#residue CYS
        $flag_residue =1;
        $residue_type =$1;
        $num_type ++;
    }

    if ($flag_residue == 1 && /\s+atom\s+/i){
#        atom N   type=NH1    charge=-0.570 end
        my $new_line = "$residue_type$_";
        print "$new_line\n";
    }

    if (/^\s+bond/){
        $flag_residue =0;
    }

    if (/^!/){
        $flag_residue =0;
    }
}
close INPUT;

print "# total residue type: $num_type\n";