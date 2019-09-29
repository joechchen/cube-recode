#!/usr/bin/env perl 
#
# test endian code
# printf("%#02x ", $_) for unpack("W*", pack L=>0x12345678); exit; # little endian on intel, proven
use strict;
use Crypt::Blowfish;
use Getopt::Std;
use String::CRC32;

# globals
my $temp="210"; # temperature to print for pla
my $material="89"; # material code 89-> PLA Magenta

my $key="221BBakerMycroft";
my $cipher = new Crypt::Blowfish $key;

my %opts=();
my $usage="usage: $0 [OPTIONS] CUBE3_FILE
  -v: verbose;
  -n: dry run;
  -m[MATERIAL_CODE]; df: $material [89->PLA Magenta];
  -t[TEMPERATURE]; df: $temp [PLA];
  -d[LEVEL]: debug level, if > 1, bfb will be logged;
  -h: Help. This message.
  ";

getopts('vhnd:m:t:', \%opts) || die $usage;
my $fn=$ARGV[0];
die $usage if ($opts{h} or not $fn);

$fn=~/^(.+)\.cube3$/;
my $fn_base=$1;
my $fnm0=$fn_base."_m0.cube3";
my $fnm=$fn_base."_m.cube3";
my $fn_bfb0="$fn_base.bfb";
my $fn_bfb=$fn_base."_m.bfb";
my $fn_fb=$fn_base."_m.bfb";
my $fn_tail=$fn_base.".tail";
my $fn_head=$fn_base.".head";
my ($xml_size,$file_size);

$material=$opts{m} if $opts{m};
$temp=$opts{t} if $opts{t};

open my $fh, '<:raw', $fn or die $!;
my ($h1,$xml,$h2); # the "header" is h1+xml+h2, offset information needs to be updated 

my $byte_read=read $fh, $h1, 274; 
$h1 =~ /^(....)(....)(..)(..)/s;
$file_size=unpack("L*",$2);
$xml_size=unpack("S*",$4);

if ($opts{d} or $opts{v}) {
  print STDERR "Loggin original bfb to $fn_bfb0 and modified to $fn_bfb.\n";
  print STDERR "Modified cube3 $fnm0 (w/o preview); $fnm (with preview).\n";
  print STDERR "1:".unpack("L*",$1),"\n"; 
  print STDERR "3:".unpack("S*",$3),"\n"; 
  print STDERR "xml_size:$xml_size\nfile_size:$file_size\n"; # cube3 file size
}

$byte_read=read $fh, $xml, $xml_size; 
if ($opts{d} or $opts{v}) {
  print STDERR $xml."<---bytes read:$byte_read\n";
}

$byte_read=read $fh, $h2, 264;  # build size etc.
$h2=~/^(....)/s;
my $bs=unpack("L*",$1);
if ($opts{d} or $opts{v}) {
  print STDERR "bfb size: $bs\n";
}

my ($body);
my $original='';

$byte_read=read $fh, $body, $bs;  # build bfb encrypted
$xml =~ /<build_crc32>(.\d+?)<\/build_crc32>/s;
my $crc=$1;

my ($tail,$bytes);
$byte_read=read $fh, $tail, 1024;  # 1k at a time
while ($byte_read == 1024) {
  $tail.=$bytes;
  $byte_read=read $fh, $bytes, 1024;  # 1k at a time
}

# decryption
while ($body =~ /(........)/gs) {
   $original.=&b2l($cipher->decrypt(&b2l($1)));
}

if ($opts{d}) {
  print STDERR "CRC32 of encrypted bfb is: ".crc32($body)," (file: $crc)\n";
}

my ($fh_out_bfb0,$fh_out_bfb,$fh_out_tail,$fh_out_head);
if ($opts{d}) {
  open $fh_out_bfb, '>', "$fn_bfb" or die "Can't open $fn_bfb for write";
  open $fh_out_bfb0, '>', "$fn_bfb0" or die "Can't open $fn_bfb0 for write";
  # keep a record of tail
  open $fh_out_tail, '>', "$fn_tail" or die "Can't open $fn_tail for write";
  binmode $fh_out_tail;
}

open my $fh_out, '>', "$fnm" or die "Can't open $fnm for write";
binmode $fh_out;

open my $fh_out0, '>', "$fnm0" or die "Can't open $fnm0 for write";
binmode $fh_out0;

if (not $opts{n}) {
  $xml =~ s#<type>ekocycle</type>#<type>cube</type>#s;
  $xml =~ s#<extruder1>(.+?)<code>(.+?)</code>#<extruder1>$1<code>$material</code>#s;
}

open my $fh_out, '>', "$fnm" or die "Can't open $fnm for write";
binmode $fh_out;

if ($opts{d}) {
  print STDERR "CRC32 of decrypted bfb is: ".crc32($original)," (file: $crc)\n";
}

if ($opts{d}) {
  print $fh_out_tail $tail;
  close $fh_out_tail;
  # keep a record of bfb
  print $fh_out_bfb0 $original;
  close $fh_out_bfb0;
}

# modify and encrypt
# based on http://www.print3dforum.com/showthread.php/1643-Running-PETG-on-Cube3?highlight=cube3+filament

if ($opts{v}) {
  print STDERR "Modifying material code to $material; and temperature to $temp.\n";
}

if (not $opts{n}) {
  $original=~s/PrinterModel:EKOCYCLE/PrinterModel:CUBE3/s;
  $original=~s/Firmware:(.*?)\r/Firmware:V1.14B\r/s;
  $original=~s/Minfirmware:(.*?)\r/Minfirmware:V1.14B\r/s;
  $original=~s/MaterialCodeE1:(.*?)\r/MaterialCodeE1:$material\r/s;

  # temperature
  # Search/replace: M104 S265 and replace with M104 S260
  # Search/replace: M204 S265 and replace with M204 S260
  $original=~s/M104 S265/M104 S260/gs;
  $original=~s/M204 S265/M204 S260/gs;
  $original=~s/M104 S250/M104 S$temp/gs;
  $original=~s/M204 S250/M204 S$temp/gs;

  #print $original;
}

if ($opts{d}) {
  # modified
  print $fh_out_bfb $original;
  close $fh_out_bfb;
}

# encrypt
$body=$original;

# padding $body to the multiple of 8 bytes 
while (length($body)%8 ne 0) {
  print STDERR "padding with 0...";
  $body.="\000";
}
print STDERR "...padding for recode done.\n";

# encryption
my $modified='';
while ($body =~ /(........)/gs) {
   $modified.=&b2l($cipher->encrypt(&b2l($1)));
}

my $new_crc=crc32($modified);
$xml =~ s/<build_crc32>(.\d+?)<\/build_crc32>/<build_crc32>$new_crc<\/build_crc32>/s;
if ($opts{d}) {
  print "New CRC32: $new_crc\n";
}

# modifying binary header
$h1 =~ /^(....)(....)(..)(..)/;
my $len=pack("S",length($xml));
my $u=pack("L",length($h1.$xml.$h2.$modified.$tail));
$h1 =~ s/^(....)(....)(..)(..)/$1$u$3$len/;
$u=pack("L*",length($modified));
$h2 =~ s/^(....)/$u/s;
print $fh_out $h1.$xml.$h2.$modified.$tail;
close $fh_out;

print $fh_out0 $modified;
close $fh_out0;


sub b2l { # big to little endian
  my $x=shift;
  return pack("L*",unpack("N*",$x))
}
