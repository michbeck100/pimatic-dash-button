module.exports = {
  title: "pimatic dash button device config schemas"
  DashButtonDevice:
    title: "DashButton config"
    type: "object"
    extensions: ["xLink"]
    properties: {
        address:
          description: "MAC address of dash button"
          type: "string"
    }
}
