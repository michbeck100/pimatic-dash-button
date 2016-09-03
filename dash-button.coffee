module.exports = (env) =>

  pcap = require 'pcap'
  stream = require 'stream'
  helper = require './helper'

  class DashButtonPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      pcapSession = pcap.createSession(@config.interface, 'arp')

      deviceConfigDef = require('./device-config-schema.coffee')

      @framework.deviceManager.registerDeviceClass 'DashButtonDevice',
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
            # List of registered Mac addresses with IEEE as of 18 July 2016 for Amazon Technologies Inc.
            # source: https://regauth.standards.ieee.org/standards-ra-web/pub/view.html#registries
            amazon_macs = {"747548","F0D2F1","8871E5","74C246","F0272D","0C47C9","A002DC","AC63BE","44650D","50F5DA","84D6D0"}
            possible_dash = helper.int_array_to_hex(packet.payload.payload.sender_ha.addr) #getting the hardware address of the possible dash
            # filter for amazon mac addresses 
            if possible_dash.slice(0,8).toString().toUpperCase().split(':').join('') in amazon_macs
              env.logger.debug 'detected new Amazon dash button with mac address ' + possible_dash
              config = {
                class: 'DashButtonDevice'
                address: possible_dash
              }
              hash = JSON.stringify(config)
              if discoveredButtons[hash]
                return
              discoveredButtons[hash] = true
              @framework.deviceManager.discoveredDevice(
                'pimatic-dash-button', 'Dash Button (' + possible_dash + ')', config
              )

        pcapSession.on('packet', packetListener)

        setTimeout(( =>
          pcapSession.removeListener("packet", packetListener)
        ), eventData.time)

  class DashButtonDevice extends env.devices.Actuator

    _listener: null

    actions:
      pressed:
        description: "dash button was pressed"

    template: "dashbutton"

    constructor: (@config, @pcapSession) ->
      @id = @config.id
      @name = @config.name
      super()

      @_listener = (raw_packet) =>
        packet = pcap.decode.packet(raw_packet) #decodes the packet
        if packet.payload.ethertype == 2054 #ensures it is an arp packet
          address = packet.payload.payload.sender_ha.addr #getting the hardware address of the possible dash
          if address == @config.address
            @pressed()

      @pcapSession.on 'packet', @_listener

    pressed: ->
      env.logger.debug @id + ' was pressed'
      emit 'dashButton'
      return Promise.resolve()

    destroy: () ->
      super()
      @pcapSession.removeListener('packet', @_listener)


  return new DashButtonPlugin()
