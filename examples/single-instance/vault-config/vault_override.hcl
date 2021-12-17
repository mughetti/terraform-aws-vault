
storage "consul" {
  address = "${consul_ip}:8500"
  path    = "vault/"
  scheme  = "http"
  service = "vault"
}