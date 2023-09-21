var https = require('http');
var fs = require('fs');
const VEDirect = require('@signalk/vedirect-serial-usb/standalone')

const consumer = new VEDirect({
  device: fs.realpathSync('DEVICE_PLACEHOLDER'),
})

consumer.on('delta', function(delta) {
  //console.log('[onDelta]', delta.updates[0].values)
  delta.updates[0].values.forEach(function(reading) {
    let name = signal_names[reading.path]
    if (name != undefined) {
      if (name == 'load_status_on' && reading.value == "on") {
          reading.value = true;
      } else if (name == 'load_status_on' && reading.value == "off") {
          reading.value = false;
      };
      let metadata = null;
      if (name == 'charging_mode' && reading.value == 'off') {
          reading.value = 0;
          metadata = {'mode': 'off'}
      } else if (name == 'charging_mode' && reading.value == 'bulk') {
          reading.value = 1;
          metadata = {'mode': 'bulk'}
      } else if (name == 'charging_mode' && reading.value == 'absorption') {
          reading.value = 2;
          metadata = {'mode': 'absorption'}
      } else if (name == 'charging_mode' && reading.value == 'float') {
          reading.value = 3;
          metadata = {'mode': 'float'}
      } else if (name == 'tracker_operation_mode') {
          reading.value = '"' + reading.value + '"';
      };
      postReadingToInfluxDB(name, reading.value, metadata)
    };
  });
})
consumer.stop() // stop the plugin, destruct the connections
consumer.start() // (re-)start the plugin

signal_names = {
  'electrical.batteries.House.voltage': 'battery_voltage',
  'electrical.batteries.House.current': 'charge_controller_current',
  'electrical.solar.Main.panelPower': 'solar_power',
  'electrical.charger.House.chargingMode': 'charging_mode',
  'electrical.solar.Main.trackerOperationMode': 'tracker_operation_mode',
  'electrical.solar.Main.load': 'load_status_on',
  'electrical.solar.Main.yieldTotal': 'yield_total',
  'electrical.solar.Main.yieldToday': 'yield_today',
  'electrical.solar.Main.maximumPowerToday': 'maximumPowerToday',
  'electrical.solar.Main.yieldYesterday': 'yieldYesterday',
  'electrical.solar.Main.maximumPowerYesterday': 'maximumPowerYesterday',
};


function postReadingToInfluxDB(series, value, metadata) {
  let nowNanos = new Date().getTime() * 1000000;
      valueStr = 'value=' + value;
      metadataStr = metadata ? ',' + JSON.stringify(metadata).replace(/{/g, '').replace(/}/g, '').replace(/"/g, '').replace(/:/g, '=') : '';
  data = series + metadataStr + ' ' + valueStr + ' ' + nowNanos;
  //console.log(data);
  var optionspost = {
      host : 'localhost',
      port : 8086,
      path : '/api/v2/write?bucket=shed_power',
      method : 'POST',
  };
  var reqPost = https.request(optionspost, function(res) {
      //console.log("statusCode: ", res.statusCode);
      res.on('data', function(d) {
          //console.log('POST result:\n');
          process.stdout.write(d);
          //console.log('\n\nPOST completed');
      });
  });

  // write the json data
  reqPost.write(data);
  reqPost.end();
  reqPost.on('error', function(e) {
      console.error(e);
  });
};
