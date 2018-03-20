module.exports = (env) =>

  pcap = require 'pcap'
  stream = require 'stream'
  helper = require './helper'
  M = env.matcher
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  _ = env.require 'lodash'

  class DashButtonPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      # List of registered Mac addresses with IEEE
      # as of 18 July 2016 for Amazon Technologies Inc.
      # source: https://regauth.standards.ieee.org/standards-ra-web/pub/view.html#registries
      amazon_macs = ["747548","F0D2F1","8871E5","74C246","F0272D","0C47C9"
        ,"A002DC","AC63BE","44650D","50F5DA","84D6D0","34D270","FCA667","78E103"]
      amazon_macs = amazon_macs
        .map((mac) ->
          "(ether[6:2] == 0x" + mac.substr(0, 4) + " and ether[8:1] == 0x" + mac.substr(4, 2) + ")")
        .reduce((l, r) -> l + " or " + r)
      # filtering arp requests only and for mac addresses directly in libpcap on kernel level
      # using a buffer size of 1 MB, should be enough for filtering ARP requests
      pcapSession =
        pcap.createSession(@config.interface, 'arp and (' + amazon_macs + ')', 1024 * 1024)

      deviceConfigDef = require('./device-config-schema.coffee')

      @framework.deviceManager.registerDeviceClass 'DashButtonDevice',
        prepareConfig: DashButtonDevice.prepareConfig
        configDef: deviceConfigDef.DashButtonDevice
        createCallback: (config, lastState) =>
          return new DashButtonDevice(config, pcapSession)

      @framework.deviceManager.on 'discover', (eventData) =>

        discoveredButtons = {}

        @framework.deviceManager.discoverMessage(
          'pimatic-dash-button', "Waiting for dash button press. Please press your dash button now."
        )

        packetListener = (raw_packet) =>
          packet = pcap.decode.packet(raw_packet) #decodes the packet
          if packet.payload.ethertype == 2054 #ensures it is an arp packet
            #getting the hardware address of the possible dash
            dash =
              helper.int_array_to_hex(packet.payload.payload.sender_ha.addr)
            env.logger.debug 'detected new Amazon dash button with mac address ' + dash
            config = {
              class: 'DashButtonDevice'
              address: dash
            }
            hash = JSON.stringify(config)
            if discoveredButtons[hash]
              return
            discoveredButtons[hash] = true
            @framework.deviceManager.discoveredDevice(
              'pimatic-dash-button', 'Dash Button (' + dash + ')', config
            )

        pcapSession.on('packet', packetListener)

        setTimeout(( =>
          pcapSession.removeListener("packet", packetListener)
        ), eventData.time)

  class DashButtonDevice extends env.devices.ButtonsDevice

    _listener: null

    @prepareConfig: (config) =>
      address = (config.address || '').replace /\W/g, ''
      if address.length is 12
        config.address = address.replace(/(.{2})/g, '$1:').toLowerCase().slice(0, -1)
      else
        env.logger.error "Invalid MAC address: #{config.address || 'Property "address" missing'}"
  
    constructor: (@config, @pcapSession) ->
      @id = @config.id
      @name = @config.name
      @config.buttons = [{"id": @id, "text": "Press"}]
      super(@config)

      @_listener = (raw_packet) =>
        packet = pcap.decode.packet(raw_packet) #decodes the packet
        if packet.payload.ethertype == 2054 #ensures it is an arp packet
          address = helper.int_array_to_hex(packet.payload.payload.sender_ha.addr)
          if address == @config.address
            @buttonPressed()

      @pcapSession.on 'packet', @_listener

    buttonPressed: ->
      env.logger.debug @id + ' was pressed'
      @_lastPressedButton = @id
      @emit 'button', @id
      return Promise.resolve()

    destroy: () ->
      super()
      @pcapSession.removeListener('packet', @_listener)

  return new DashButtonPlugin()
