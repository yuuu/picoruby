#include "../../include/net.h"
#include "lwipopts.h"
#include "pico/cyw43_arch.h"
#include "lwip/altcp_tls.h"

#include "include/common.h"

/* platform-dependent definitions */

/* state values for TCP connection */
#define NET_TCP_STATE_NONE               0
#define NET_TCP_STATE_CONNECTION_STARTED 1
#define NET_TCP_STATE_CONNECTED          2
#define NET_TCP_STATE_WAITING_PACKET     3
#define NET_TCP_STATE_PACKET_RECVED      4
#define NET_TCP_STATE_FINISHED           6
#define NET_TCP_STATE_ERROR              99

/* TCP connection struct */
typedef struct tcp_connection_state_str
{
  int state;
  struct altcp_pcb *pcb;
  mrbc_value *send_data;
  mrbc_value *recv_data;
  mrbc_vm *vm;
  struct altcp_tls_config *tls_config;
} tcp_connection_state;

/* end of platform-dependent definitions */

static void
TCPClient_free_tls_config(tcp_connection_state *cs)
{
  if (cs && cs->tls_config) {
    altcp_tls_free_config(cs->tls_config);
  }
}

static err_t
TCPClient_recv_cb(void *arg, struct altcp_pcb *pcb, struct pbuf *pbuf, err_t err)
{
  tcp_connection_state *cs = (tcp_connection_state *)arg;
  if (pbuf != NULL) {
    char *tmpbuf = mrbc_alloc(cs->vm, pbuf->tot_len + 1);
    struct pbuf *current_pbuf = pbuf;
    int offset = 0;
    while (current_pbuf != NULL) {
      pbuf_copy_partial(current_pbuf, tmpbuf + offset, current_pbuf->len, 0);
      offset += current_pbuf->len;
      current_pbuf = current_pbuf->next;
    }
    tmpbuf[pbuf->tot_len] = '\0';
    mrbc_string_append_cbuf(cs->recv_data, tmpbuf, pbuf->tot_len);
    mrbc_free(cs->vm, tmpbuf);
    altcp_recved(pcb, pbuf->tot_len);
    cs->state = NET_TCP_STATE_PACKET_RECVED;
    pbuf_free(pbuf);
  } else {
    cs->state = NET_TCP_STATE_FINISHED;
  }
  TCPClient_free_tls_config(cs);
  return ERR_OK;
}

static err_t
TCPClient_sent_cb(void *arg, struct altcp_pcb *pcb, u16_t len)
{
  // do nothing as of now
  return ERR_OK;
}

static err_t
TCPClient_connected_cb(void *arg, struct altcp_pcb *pcb, err_t err)
{
  tcp_connection_state *cs = (tcp_connection_state *)arg;
  cs->state = NET_TCP_STATE_CONNECTED;
  return ERR_OK;
}

static err_t
TCPClient_poll_cb(void *arg, struct altcp_pcb *pcb)
{
  tcp_connection_state *cs = (tcp_connection_state *)arg;
  cs->state = NET_TCP_STATE_FINISHED;
  return ERR_OK;
}

static void
TCPClient_err_cb(void *arg, err_t err)
{
  tcp_connection_state *cs = (tcp_connection_state *)arg;
  console_printf("Error with: %d\n", err);
  cs->state = NET_TCP_STATE_ERROR;
  TCPClient_free_tls_config(cs);
}

static tcp_connection_state *
TCPClient_new_connection(mrbc_value *send_data, mrbc_value *recv_data, mrbc_vm *vm)
{
  tcp_connection_state *cs = (tcp_connection_state *)mrbc_raw_alloc(sizeof(tcp_connection_state));
  cs->tls_config = NULL;
  cs->state = NET_TCP_STATE_NONE;
  cs->pcb = altcp_new(NULL);
  altcp_recv(cs->pcb, TCPClient_recv_cb);
  altcp_sent(cs->pcb, TCPClient_sent_cb);
  altcp_err(cs->pcb, TCPClient_err_cb);
  altcp_poll(cs->pcb, TCPClient_poll_cb, 10);
  altcp_arg(cs->pcb, cs);
  cs->send_data = send_data;
  cs->recv_data = recv_data;
  cs->vm        = vm;
  return cs;
}

static tcp_connection_state *
TCPClient_new_tls_connection(const char *host, mrbc_value *send_data, mrbc_value *recv_data, mrbc_vm *vm)
{
  tcp_connection_state *cs = (tcp_connection_state *)mrbc_raw_alloc(sizeof(tcp_connection_state));
  cs->state = NET_TCP_STATE_NONE;

  struct altcp_tls_config *tls_config = altcp_tls_create_config_client(NULL, 0);
  cs->pcb = altcp_tls_new(tls_config, IPADDR_TYPE_V4);
  cs->tls_config = tls_config;
  mbedtls_ssl_set_hostname(altcp_tls_context(cs->pcb), host);
  altcp_recv(cs->pcb, TCPClient_recv_cb);
  altcp_sent(cs->pcb, TCPClient_sent_cb);
  altcp_err(cs->pcb, TCPClient_err_cb);
  altcp_poll(cs->pcb, TCPClient_poll_cb, 10);
  altcp_arg(cs->pcb, cs);
  cs->send_data = send_data;
  cs->recv_data = recv_data;
  cs->vm        = vm;
  return cs;
}

static tcp_connection_state *
TCPClient_connect_impl(ip_addr_t *ip, const char *host, int port, mrbc_value *send_data, mrbc_value *recv_data, mrbc_vm *vm, bool is_tls)
{
  tcp_connection_state *cs;
  if (is_tls) {
    cs = TCPClient_new_tls_connection(host, send_data, recv_data, vm);
  } else {
    cs = TCPClient_new_connection(send_data, recv_data, vm);
  }
  cyw43_arch_lwip_begin();
  altcp_connect(cs->pcb, ip, port, TCPClient_connected_cb);
  cyw43_arch_lwip_end();
  cs->state = NET_TCP_STATE_CONNECTION_STARTED;
  return cs;
}

static int
TCPClient_poll_impl(tcp_connection_state **pcs)
{
  if (*pcs == NULL)
    return 0;
  tcp_connection_state *cs = *pcs;
  switch(cs->state)
  {
    case NET_TCP_STATE_NONE:
      break;
    case NET_TCP_STATE_CONNECTION_STARTED:
      break;
    case NET_TCP_STATE_WAITING_PACKET:
      break;
    case NET_TCP_STATE_CONNECTED:
      cs->state = NET_TCP_STATE_WAITING_PACKET;
      cyw43_arch_lwip_begin();
      altcp_write(cs->pcb, cs->send_data->string->data, cs->send_data->string->size, 0);
      altcp_output(cs->pcb);
      cyw43_arch_lwip_end();
      break;
    case NET_TCP_STATE_PACKET_RECVED:
      cs->state = NET_TCP_STATE_WAITING_PACKET;
      break;
    case NET_TCP_STATE_FINISHED:
      cyw43_arch_lwip_begin();
      altcp_close(cs->pcb);
      cyw43_arch_lwip_end();
      mrbc_free(cs->vm, cs);
      *pcs = NULL;
      return 0;
      break;
    case NET_TCP_STATE_ERROR:
      mrbc_free(cs->vm, cs);
      *pcs = NULL;
      return 0;
      break;
  }
  return cs->state;
}

mrbc_value
TCPClient_send(const char *host, int port, mrbc_vm *vm, mrbc_value *send_data, bool is_tls)
{
  ip_addr_t ip;
  ip4_addr_set_zero(&ip);
  mrbc_value ret;
  Net_get_ip(host, &ip);
  if(!ip4_addr_isloopback(&ip)) {
    char ip_str[16];
    ipaddr_ntoa_r(&ip, ip_str, 16);
    mrbc_value recv_data = mrbc_string_new(vm, NULL, 0);
    tcp_connection_state *cs = TCPClient_connect_impl(&ip, host, port, send_data, &recv_data, vm, is_tls);
    while(TCPClient_poll_impl(&cs))
    {
      sleep_ms(200);
    }
    // recv_data is ready after connection is complete
    ret = recv_data;
  } else {
    ret = mrbc_nil_value();
  }
  return ret;
}

