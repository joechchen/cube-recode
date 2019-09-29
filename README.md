# This is a quick and dirty script to recode an Ekocycle file to print on Cube3
1) It runs on Linux and OSX (never tried on Windows, and will not);
2) It only changes material code, destination printer (Cube3, that is) and temperature.

# To use:
1) In Cube Print (4.03) print (save-to-file) to Offline EKOCYCLE Cube;
2) Run:
```sh
cube-recode.pl file.cube3
```
3) Either use USB key to print file_m0.cube3 or use Cube Print to open file_m.cube3 for Wifi printing;
4) Use -h for help and read the code for documentation;
5) Very limited tests -- I only have the left nozzle working and two PLA cartridges (modified to use any bulk filament of course).

# CPAN modules required:
1) Crypt::Blowfish
2) String::CRC32
3) Getopt::Std

# Feel free to modify and improve, sorry for the messy coding style.
