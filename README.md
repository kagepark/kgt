# kgt
Kage Engineer tools
Keep moving original code to github.com site.
This is GPL license(Opensource)

Install:
# git clone https://github.com/kagepark/kgt.git
# cd kgt
# ./bin/kgt setup
# . /etc/profile.d/kgt.sh

Installed binary test file will be in /global/kgt/<pkg name>/....
when you want directly handle the binary file then you can use above directory

##### Command #####
# kgt help      # for help
# kgt <command> <hostname rule> [<options>] # usually help when need options. if not need options then just run.

##### Hostname rule start #####
# Make a hostname with syntax #
-h <hostname> syntax
  test-000[01-09] 
  test-00[001-008,100-200]
  test-001 test-0008
  test[001-100]

or

# Find hostname from /etc/hosts file
-g test         => It will find all of test-XXXXX hostname from /etc/hosts file.
-g test -nodash => it will find hostname not included dash
-g test -dash   => it will find hostname (included dash)
##### Hostname rule end #####
