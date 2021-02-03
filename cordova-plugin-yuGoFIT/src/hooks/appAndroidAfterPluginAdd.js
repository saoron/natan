#!/usr/bin/env node

module.exports = function (context) {
  // Make sure android platform is part of build
  if (!context.opts.platforms.includes('android')) return;

  var fs = require('fs');
  var path = require('path');
  const { ConfigParser } = require('cordova-common');

  var config_xml = path.join(context.opts.projectRoot, 'config.xml');
  var et = context.requireCordovaModule('cordova-common');
  var appConfig = new ConfigParser(config_xml);

  //copy MainActivity.java to ${appConfig.packageName()}
  fs.copyFileSync(
    'plugins/cordova-plugin-yugofit/src/hooks/MainActivity.java',
    'platforms/android/app/src/main/java/com/' +
      appConfig.name().toLowerCase() +
      '/MainActivity.java'
  );
};
