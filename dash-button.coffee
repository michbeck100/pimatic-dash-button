module.exports = (env) =>

  pcap = require 'pcap'
  stream = require 'stream'

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
            possible_dash = packet.payload.payload.sender_ha.addr #getting the hardware address of the possible dash
            env.logger.debug 'detected new dash button with address ' + possible_dash
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
