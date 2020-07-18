# kgt
Kage Engineer tools
Keep moving original code to github.com site.
This is GPL license(Opensource)

Install:
```
# git clone https://github.com/kagepark/kgt.git
# cd kgt
# ./bin/kgt setup
# . /etc/profile.d/kgt.sh
```
Installed-binary-packages are in /global/kgt/<pkg name>/....
when you want directly handle the binary file then you can use above directory

## Command
```
# kgt help      # for help
# kgt <command> <hostname rule> [<options>] # usually help when need options. if not need options then just run.
```
## Hostname rule start
** Make a hostname with syntax **
```
-h <hostname> syntax
  test-000[01-09] 
  test-00[001-008,100-200]
  test-001 test-0008
  test[001-100]
```
or
** Find hostname from /etc/hosts file **
```
-g test         => It will find all of test-XXXXX hostname from /etc/hosts file.
-g test -nodash => it will find hostname not included dash
-g test -dash   => it will find hostname (included dash)
```


## MUNGE/SLURM Install
Initial simple install script after automatically download file

- MUNGE Install
```
# cd <kgt home>/share
# bash munge_install_uninstall.sh install https://github.com/dun/munge/archive/munge-0.5.13.tar.gz /global/opt/munge
```
- MUNGE Uninstall
```
# cd <kgt home>/share
# bash munge_install_uninstall.sh uninstall
```

- SLURM Install
```
# cd <kgt home>/share
# bash slurm_install_uninstall.sh install https://download.schedmd.com/slurm/slurm-17.11.4.tar.bz2 /global/opt/slurm /global/opt/munge TEST mgt enp0s3
```

- SLURM uninstall
```
# cd <kgt home>/share
# bash slurm_install_uninstall.sh uninstall
```
