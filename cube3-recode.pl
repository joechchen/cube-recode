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
my $material="86"; # material code 89-> PLA Magenta, 86-> PLA White

# initial proceduer <- CubePro 1.88's initial is broken on Cube3:
my $init="M227 P450 S450 G450 F600\r\nM228 P0 S450\r\nM231 P0 S0\r\nM232 P5000 S5000\r\nM233 P1000\r\nM106 P100\r\nG4 P60\r\nM601 P3 S60 F5\r\nM542\r\nM240 X450\r\nM240 Y400\r\nM228 P0 S1\r\nM227 P1 S1 G1000 F1000\r\nM601 P8 S60 F5\r\nM240 S450\r\nM204 S155 P1\r\nM104 S155 P1\r\nG1 X-100.500 Y0.000 Z5.0575 F7000.0\r\nM104 S225\r\nG4 P15\r\nM551 P850 S50\r\nM104 S155 P1\r\nM601 P2 S60 F5\r\nM103\r\nM240 X400\r\nM240 Y450\r\nM543\r\nM107\r\nM107\r\n";

# global rules, will go throuh the encoding first
my %RULE0=(
  'Highest temperature E1: Search/replace: M104 S265 and replace with M104 S260' => '$original=~s/M104 S265/M104 S260/gs',
  'Highest temperature E2: Search/replace: M204 S265 and replace with M204 S260' => '$original=~s/M204 S265/M204 S260/gs',
  'Removing mv to wastebin' => '$original=~s/G1 X-95.500 Y0.000 Z5.0575 F7000.0\r\n//gs',
  'Slowing the first touchdown' => '$original=~s/M228 P0 S450\r\nM227 P450 S450 G450 F600/M228 P0 S250\r\nM227 P250 S250 G450 F600/gs',
);

my %RULE_PLA=(
   'E1 200C => 145c' => '$original=~s/M104 S200/M104 S145/gs',
   'E2 200C => 145c' => '$original=~s/M204 S200/M204 S145/gs',
   'E1 210C => 155c' => '$original=~s/M104 S210/M104 S155/gs',
   'E2 210C => 155c' => '$original=~s/M204 S210/M204 S155/gs',
   'Cap to 235C' => '$original=~s/M([12])04 S24\d/M{$1}04 S235/gs',
);


my $key="221BBakerMycroft";
my $cipher = new Crypt::Blowfish $key;

my %opts=();
my $usage="usage: $0 [OPTIONS] [CUBE3_FILE|CUBEPRO_FILE]
  -v: verbose;
  -x: decode xml; 
  -n: dry run (for pack/unpack test, e.g.);
  -m[MATERIAL_CODE] df: chip $material [89->PLA Magenta, 86->PLA White];
  -t[TEMPERATURE] df: print temperature ${temp}C, on top of PLA or PETG/ABS profile;
  -r: remove retract (M103) completely (df: no);
  -P: PETG/ABS profile, df: PLA profile;
  -e[BFB_CODE]: replace the bfb code with the file content of BFB_CODE;
  -i: in-place, the original file will be over written (cubepro->cube3 though);
  -o[OUTPUT_FILENAME]: specific output file name, eg ~/Library/Application\ Support/com.threedsystems.Cubify/CubeFiles/a_1.cube3;
  -s: create a cube3 file (.._m0.cube3) without preview and meta data (df: not creating);
  -d[LEVEL]: debug level, if > 1, bfb will be logged;
  -h: Help. This message.
  ";

getopts('xvhnd:m:t:ie:sPro:', \%opts) || die $usage;
my $fn=$ARGV[0];
die $usage if ($opts{h} or not $fn);

my $fn_base;
my $PRO=undef; # default cube3
if ($fn=~/^(.+)\.cube3$/) { # cube3
  $fn_base=$1;
  print STDERR "Cube3 input file, base filename \"$fn_base\".\n" if $opts{v} or $opts{d};
} elsif ($fn=~/^(.+)\.cubepro$/) {
  $fn_base=$1;
  $PRO=1;
  print STDERR "CubePro input file, base filename \"$fn_base\".\n" if $opts{v} or $opts{d};
}

if ($opts{x}) { # xml mode
  $fn=~/^(.+)\.xml$/;
}
my $fnm0=$fn_base."_m0.cube3";
my $fnm=$fn_base."_m.cube3";
my $fn_bfb0="$fn_base.bfb";
my $fn_bfb=$fn_base."_m.bfb";
my $fn_fb=$fn_base."_m.bfb";
my $fn_tail=$fn_base.".tail";
my ($xml_size,$file_size);

$material=$opts{m} if $opts{m};
$temp=$opts{t} if $opts{t};

open my $fh, '<:raw', $fn or die $!;
my ($h1,$xml,$h2); # the "header" is h1+xml+h2, offset information needs to be updated 
if ($opts{x}) {
  my $byte_read;
  my $body='';
  my $bytes;
  do {
    $byte_read=read $fh, $bytes, 1024;  # 1k at a time
    $body.=$bytes;
  } while ($byte_read == 1024);

  my $original='';
  while ($body =~ /(........)/gs) {
    $original.=&b2l($cipher->decrypt(&b2l($1)));
  }
  print $original;

  exit;
}
my $byte_read=read $fh, $h1, 274; 
if ($opts{d}>4) { # dump binary headers
  open my $ff, '>', "$fn_base.h1" or die "Can't open $fn_base.h1 for write";
  binmode $ff;
  print $ff $h1;
  close $ff;
}
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

if ($opts{i}) { # in-place
  if ($PRO) { # cubepro input, always output cube3
    $fnm="$fn_base.cube3";
  } else {
    $fnm=$fn;
  }
}

if ($opts{o}) {
  $fnm=$opts{o};
  print "Output file override to $fnm..\n";
}

$byte_read=read $fh, $h2, 264;  # build size etc.
if ($opts{d}>4) { # dump binary headers
  open my $ff, '>', "$fn_base.h2" or die "Can't open $fn_base.h2 for write";
  binmode $ff;
  print $ff $h2;
  close $ff;
}
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
do {
  $byte_read=read $fh, $bytes, 1024;  # 1k at a time
  $tail.=$bytes;
} while ($byte_read == 1024);

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

if (not $opts{n}) {
  if ($PRO) {
    $xml =~ s#<type>cubepro</type>#<type>cube</type>#is;
    $xml =~ s#<Cube_Creation>(.+?)</Cube_Creation>-->\n##is;
  }
  $xml =~ s#<type>ekocycle</type>#<type>cube</type>#s;
  $xml =~ s#<extruder1>(.+?)<code>(.+?)</code>#<extruder1>$1<code>$material</code>#s;
}

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
  $original=~s/PrinterModel:CUBEPRO/PrinterModel:CUBE3/s;
  $original=~s/Firmware:(.*?)\r/Firmware:V1.14B\r/s;
  $original=~s/Minfirmware:(.*?)\r/Minfirmware:V1.14B\r/s;
  $original=~s/MaterialCodeE1:(.*?)\r/MaterialCodeE1:$material\r/s;

  # temperature
  # Search/replace: M104 S265 and replace with M104 S260
  # Search/replace: M204 S265 and replace with M204 S260
  while ( my ($k, $v) = each %RULE0 ) {
    print STDERR "eval($v) for $k\n" if $opts{d}>2;
    if (eval($v)) {
      print STDERR "$k: HIT!\n";
    }
  }
  if (not $opts{P}) { # assuming PLA
    while ( my ($k, $v) = each %RULE_PLA ) {
      print STDERR "eval($v) for $k\n" if $opts{d}>2;
      if (eval($v)) {
        print STDERR "$k: HIT!\n";
      }
    }

    # there are some 'M204 S240 P1' left in Ekocycle? too high?
  }
  # on top of profile temperature change
  if ($PRO) {
    print STDERR "ASSUMING CubePro ABS profile...\n" if $opts{v} or $opts{d};
    $original=~s/\^Time(.+?)\r\n(.+?)\^InitComplete/\^Time$1\r\n$init^InitComplete/gs;
    $original=~s/\^40-CHUCK(.+?)\r\n//gs;
    $original=~s/\^ForceMinfirmware(.+?)\r\n//gs;
    if ($original=~s/M104 S245/M104 S$temp/gs) {
      print STDERR "E1 printing temperature changed to $temp!\n";
    }
    if ($original=~s/M204 S250/M204 S$temp/gs) {
      print STDERR "E2 printing temperature changed to $temp!\n";
    }
  } else { # Ekocycle
    if ($original=~s/M104 S250/M104 S$temp/gs) {
      print STDERR "E1 printing temperature changed to $temp!\n";
    }
    if ($original=~s/M204 S250/M204 S$temp/gs) {
      print STDERR "E2 printing temperature changed to $temp!\n";
    }
  }

  # test
  $original=~s/M204 S240/M204 S$temp/gs;

  if ($opts{r}) { # remove retract
    $original=~s/M103\r\n//gs;
    print STDERR "All retract (M103) removed!\n";
  }
  #print $original;
}

my $modified='';
if ($opts{e}) { # we are provided with a bfb file
  open my $fhb, '<:raw', $opts{e} or die $!;
  $body = do { local $/; <$fhb> };
  close $fhb;
} else {
  $body=$original;
}

if ($opts{d}) {
  # modified
  print $fh_out_bfb $body;
  close $fh_out_bfb;
}

# padding $body to the multiple of 8 bytes 
while (length($body)%8 ne 0) {
  print STDERR "padding with 0...";
  $body.="\000";
}
print STDERR "...padding for recode done.\n";

# encryption
while ($body =~ /(........)/gs) {
  $modified.=&b2l($cipher->encrypt(&b2l($1)));
}

my $new_crc=crc32($modified);
$xml =~ s/<build_crc32>(.\d+?)<\/build_crc32>/<build_crc32>$new_crc<\/build_crc32>/s;
if ($opts{d}) {
  print "New CRC32: $new_crc\n";
}

# changed the build file from cubepro to cube3 if necessary
if ($PRO and not $opts{n}) {
  $xml =~ /<build_file>(.+?)<\/build_file>/s;
  my $build_file=$1;
  my $new_build_file=$build_file;
  $new_build_file=~s/\.cubepro/\.cube3/s;
  $xml =~ s/<build_file>$build_file<\/build_file>/<build_file>$new_build_file<\/build_file>/s;
  print STDERR "CubePro new XML lenght:".length($xml)."\n" if $opts{d}>4;
  $h2 =~ s/$build_file/$new_build_file\0\0/s;
}


# modifying binary header
$h1 =~ /^(....)(....)(..)(..)/s;
my $len=pack("S",length($xml));
my $u=pack("L",length($h1.$xml.$h2.$modified.$tail));
$h1 =~ s/^(....)(....)(..)(..)/$1$u$3$len/s;
$u=pack("L*",length($modified));
$h2 =~ s/^(....)/$u/s;

open my $fh_out, '>', "$fnm" or die "Can't open $fnm for write";
binmode $fh_out;
print $fh_out $h1.$xml.$h2.$modified.$tail;
close $fh_out;

if ($opts{s}) {
  open my $fh_out0, '>', "$fnm0" or die "Can't open $fnm0 for write";
  binmode $fh_out0;
  print $fh_out0 $modified;
  close $fh_out0;
}

sub b2l { # big to little endian
  my $x=shift;
  return pack("L*",unpack("N*",$x))
}

