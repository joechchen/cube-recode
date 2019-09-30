# This is a quick and dirty script to recode an Ekocycle file to print on Cube3
1) It runs on Linux and Mac OSX (never tried on Windows, and will not);
2) It only changes material code, destination printer (Cube3, that is) and temperature.

# To use:
1) In Cube Print (4.03) print (save-to-file, for 2a; or save-to-my-library, for 2b) to Offline EKOCYCLE Cube;
2) Run:
```sh
cube3-recode.pl file.cube3
```
a) Either use USB key to print file_m0.cube3 (needs -s option) or use Cube Print to open file_m.cube3 for Wifi printing;
or 
b) In-place recode the file, tested only on Mac OSX
```sh
cube3-recode.pl -i file.cube3 # can be used on ~/Library/Application\ Support/com.threedsystems.Cubify/CubeFiles/file.cube3 directly
```

4) Use -h for help and read the code for documentation;
5) Very limited tests -- I only have the left nozzle working and two PLA cartridges (modified to use any bulk filament of course).

# CPAN modules required:
1) Crypt::Blowfish
2) String::CRC32
3) Getopt::Std

# Load filamen code shamely copied from:
http://www.print3dforum.com/showthread.php/1014-Cube-3-Extruder-Hub-V2-FTF-(Free-The-Filament)?highlight=load+filament

# Feel free to modify and improve, sorry for the messy coding style.
