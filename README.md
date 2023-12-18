```bash
yum -y install wget git
git clone https://github.com/yun-onl/lcmp.git
cd lcmp
chmod 755 *.sh
./lcmp.sh 2>&1 | tee lcmp.log
```

- If your server's OS: Debian 10+ / Ubuntu 20.04+
```bash
apt-get -y install wget git
git clone https://github.com/yun-onl/lcmp.git
cd lcmp
chmod 755 *.sh
./lcmp.sh 2>&1 | tee lcmp.log
```