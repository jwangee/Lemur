
/* -*_ p4_14 -*- */
#include <tofino/intrinsic_metadata.p4>
#include <tofino/constants.p4>

#define BESS_PORT 44
#define CPU_PORT 9
#define TYPE_VLAN 0x0810
#define TYPE_NSH 0x894F
#define TYPE_NSH_IPV4 0x1
#define TYPE_NSH_VLAN 0x6
#define TYPE_IPV4 0x0800
#define TYPE_IPV6 0x0816
#define ETHERTYPE_IPV4 0x0800
#define ETHERTYPE_VLAN 0x8100
#define IPV4_FORWARD_TABLE_SIZE 5000
#define TYPE_TCP 0x06
#define TYPE_UDP 0x11
#define ACL_TABLE_SIZE 50
#define NAT_TABLE_SIZE 2000


/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/


header_type ethernet_t {
	fields{
		dstAddr : 48;
		srcAddr : 48;
		etherType : 16;
	}
}

header_type vlan_t {
	fields{
		TCI : 16;
		nextType : 16;
	}
}

header_type nsh_t {
	fields{
		version : 2;
		oBit : 1;
		uBit : 1;
		ttl : 6;
		totalLength : 6;
		unsign : 4;
		md : 4;
		nextProto : 8;
		spi : 24;
		si : 8;
		context : 128;
	}
}

header_type ipv4_t {
	fields{
		version : 4;
		ihl : 4;
		diffserv : 8;
		totalLen : 16;
		identification : 16;
		flags : 3;
		fragOffset : 13;
		ttl : 8;
		protocol : 8;
		hdrChecksum : 16;
		srcAddr : 32;
		dstAddr : 32;
	}
}

header_type ipv6_t {
	fields{
		version : 4;
		traffic_class : 8;
		flow_label : 20;
		payload_len : 16;
		next_hdr : 8;
		hop_limit : 8;
		srcAddr : 64;
		dstAddr : 64;
	}
}

header_type tcp_t {
	fields{
		srcPort : 16;
		dstPort : 16;
		seqNo : 32;
		ackNo : 32;
		dataOffset : 4;
		res : 3;
		ecn : 3;
		ctrl : 6;
		window : 16;
		checksum : 16;
		urgentPtr : 16;
	}
}

header_type udp_t {
	fields{
		srcPort : 16;
		dstPort : 16;
		hdr_length : 16;
		checksum : 16;
	}
}


header_type metadata_t {
	fields {
		service_path_id : 24;
		service_id : 8;
		prev_spi : 8;
		prev_si : 8;
		forward_flag : 1;
		controller_flag : 1;
		nsh_flag : 1;
		drop_flag : 1;
		ipv4_forward_table_miss_flag : 4;
		acl_table_miss_flag : 1;
		if_index : 9;
		is_ext_if : 1;
		nat_table_miss : 1;
		ipv4_sa : 32;
		ipv4_da : 32;
		tcp_sp : 16;
		tcp_dp : 16;
		if_ipv4_addr : 32;
		if_mac_addr : 48;
	}
}

metadata metadata_t meta;

header ethernet_t ethernet;
header vlan_t vlan;
header nsh_t nsh;
header ipv4_t ipv4;
header ipv6_t ipv6;
header tcp_t tcp;
header udp_t udp;



/*************************************************************************
************************  P A R S E R  **********************************
*************************************************************************/

parser start {
	// start with ethernet parsing
	return parse_ethernet;
}

parser parse_ethernet {
	extract(ethernet);
	return select(latest.etherType) {
		TYPE_IPV4 : parse_ipv4;
		TYPE_IPV6 : parse_ipv6;
		TYPE_NSH : parse_nsh;
		TYPE_VLAN : parse_vlan;
		ETHERTYPE_IPV4 : parse_ipv4;
		ETHERTYPE_VLAN : parse_vlan;
		default: ingress;
	}
}

parser parse_vlan {
	extract(vlan);
	return select(latest.nextType) {
		TYPE_IPV4 : parse_ipv4;
		ETHERTYPE_IPV4 : parse_ipv4;
		default: ingress;
	}
}

parser parse_ipv4 {
	extract(ipv4);
	return select(latest.protocol) {
		TYPE_TCP : parse_tcp;
		TYPE_UDP : parse_udp;
		default: ingress;
	}
}

parser parse_ipv6 {
	extract(ipv6);
	return ingress;
}

parser parse_nsh {
	extract(nsh);
	return select(latest.nextProto) {
		TYPE_NSH_IPV4 : parse_ipv4;
		TYPE_NSH_VLAN : parse_vlan;
		default: ingress;
	}
}

parser parse_tcp {
	extract(tcp);
	return ingress;
}

parser parse_udp {
	extract(udp);
	return ingress;
}



/************************  I N G R E S S  **********************************/
/* Code from sys_default */
action sys_send_to_bess() {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, BESS_PORT);
}

action sys_send_to_controller() {
    // modify_field(ig_intr_md_for_tm.ucast_egress_port, CPU_PORT);
    modify_field(ig_intr_md_for_tm.copy_to_cpu, 1);
}

action sys_pdrop() {
	drop();
}

action sys_set_drop_flag() {
	modify_field(meta.drop_flag, 1);
}

action sys_valid_nsh_header() {
    add_header(nsh);
    sys_setup_nsh_header();
    modify_field(meta.service_id, 0);
}

action sys_handle_next_proto_vlan() {
    modify_field(ethernet.etherType, TYPE_NSH);
    modify_field(nsh.nextProto, TYPE_NSH_VLAN); // VLAN
}

action sys_handle_next_proto_ipv4() {
    modify_field(ethernet.etherType, TYPE_NSH);
    modify_field(nsh.nextProto, TYPE_NSH_IPV4); // IPv4
}

action sys_setup_nsh_header() {
    modify_field(nsh.version, 0);
    modify_field(nsh.oBit, 0);
    modify_field(nsh.uBit, 0);
    modify_field(nsh.ttl, 63);
    modify_field(nsh.totalLength,0x6);
    modify_field(nsh.unsign, 0);
    modify_field(nsh.md, 0x1); // fixed length
    modify_field(nsh.spi, meta.service_path_id);
    modify_field(nsh.si, meta.service_id);
    modify_field(nsh.context, 0x1234);
}

action sys_remove_nsh_header() {
    modify_field(meta.service_path_id, nsh.spi);
    modify_field(meta.service_id, nsh.si);
    modify_field(ethernet.etherType, TYPE_IPV4);
    remove_header(nsh);
}

table sys_send_to_bess_apply {
    actions { sys_send_to_bess; }
    default_action : sys_send_to_bess();
    size : 0;
}

table sys_send_to_controller_apply {
    actions { sys_send_to_controller; }
    default_action : sys_send_to_controller();
    size : 0;
}

table sys_drop_apply {
	actions { sys_pdrop; }
	default_action : sys_pdrop();
	size : 0;
}

table sys_set_drop_flag_apply {
	actions { sys_set_drop_flag; }
	default_action : sys_set_drop_flag();
	size : 0;
}

table sys_valid_nsh_header_apply {
    actions { sys_valid_nsh_header; }
    default_action : sys_valid_nsh_header();
    size : 0;
}

table sys_handle_next_proto_vlan_apply {
    actions { sys_handle_next_proto_vlan; }
    default_action : sys_handle_next_proto_vlan();
    size : 0;
}

table sys_handle_next_proto_ipv4_apply {
    actions { sys_handle_next_proto_ipv4; }
    default_action : sys_handle_next_proto_ipv4();
    size : 0;
}

table sys_remove_nsh_header_apply {
    actions { sys_remove_nsh_header; }
    default_action : sys_remove_nsh_header();
    size : 0;
}

/* Code from anon_10 */
action vlan_rm_do_VLAN_decap() {
    modify_field(ethernet.etherType, vlan.nextType);
    remove_header(vlan);
}

action vlan_rm_init_metadata() {
}

table vlan_rm_4_1_rm_vlan {
	actions {
		vlan_rm_do_VLAN_decap;
	}
	default_action : vlan_rm_do_VLAN_decap;
}

table vlan_rm_4_1_init_metadata_apply {
    actions { vlan_rm_init_metadata; }
    default_action : vlan_rm_init_metadata;
    size:0;
}

/* Code from nsh_4_2 */
action nshencap_set_nsh_flag() {
    modify_field(meta.nsh_flag, 1);
}

table nshencap_4_2_set_nsh_flag_apply {
    actions { nshencap_set_nsh_flag; }
    default_action : nshencap_set_nsh_flag;
    size : 0;
}

/* Code from anon_12 */
action ipv4forward_set_dmac(dstAddr) {
	modify_field(ethernet.srcAddr, ethernet.dstAddr);
	modify_field(ethernet.dstAddr, dstAddr);
}

action ipv4forward_ipv4_forward_table_hit(dstAddr, port) {
	ipv4forward_set_dmac(dstAddr);
	modify_field(ig_intr_md_for_tm.ucast_egress_port, port);
	modify_field(meta.ipv4_forward_table_miss_flag, 0);
}

action ipv4forward_ipv4_forward_table_miss() {
    modify_field(meta.ipv4_forward_table_miss_flag, 1);
}

action ipv4forward_init_metadata() {
	modify_field(meta.ipv4_forward_table_miss_flag, 0);
}

action ipv4forward_drop_pkt() {
    modify_field(meta.drop_flag, 1);
}

table ipv4forward_4_3_ipv4_forward_table {
	reads {
		ipv4.dstAddr: lpm;
	}
	actions {
		ipv4forward_ipv4_forward_table_hit;
		ipv4forward_ipv4_forward_table_miss;
	}
	default_action : ipv4forward_ipv4_forward_table_miss;
	size : IPV4_FORWARD_TABLE_SIZE;
}

table ipv4forward_4_3_init_metadata_apply {
    actions { ipv4forward_init_metadata; }
    default_action : ipv4forward_init_metadata;
    size:0;
}

table ipv4forward_4_3_drop_pkt_apply {
    actions { ipv4forward_drop_pkt; }
    default_action : ipv4forward_drop_pkt;
    size : 0;
}

/* Code from nsh_3_1 */
table nshencap_3_1_set_nsh_flag_apply {
    actions { nshencap_set_nsh_flag; }
    default_action : nshencap_set_nsh_flag;
    size : 0;
}

/* Code from anon_8 */
action acl_drop() {
	modify_field(meta.drop_flag, 1);
}

action acl_acl_table_hit() {
    modify_field(meta.acl_table_miss_flag, 0);
}

action acl_acl_table_miss() {
    modify_field(meta.acl_table_miss_flag, 1);
    acl_drop();
}

action acl_init_metadata() {
}

table acl_3_2_acl_table {
	reads {
		ipv4.srcAddr: ternary;
		ipv4.dstAddr: ternary;
		tcp.srcPort: ternary;
		tcp.dstPort: ternary;
	}
	actions {
		acl_acl_table_hit;
		acl_acl_table_miss;
	}
	default_action : acl_acl_table_miss();
	size : ACL_TABLE_SIZE;
}

table acl_3_2_init_metadata_apply {
	actions { acl_init_metadata; }
	default_action : acl_init_metadata;
	size : 0;
}

/* Code from anon_9 */
table ipv4forward_3_3_ipv4_forward_table {
	reads {
		ipv4.dstAddr: lpm;
	}
	actions {
		ipv4forward_ipv4_forward_table_hit;
		ipv4forward_ipv4_forward_table_miss;
	}
	default_action : ipv4forward_ipv4_forward_table_miss;
	size : IPV4_FORWARD_TABLE_SIZE;
}

table ipv4forward_3_3_init_metadata_apply {
    actions { ipv4forward_init_metadata; }
    default_action : ipv4forward_init_metadata;
    size:0;
}

table ipv4forward_3_3_drop_pkt_apply {
    actions { ipv4forward_drop_pkt; }
    default_action : ipv4forward_drop_pkt;
    size : 0;
}

/* Code from nsh_2_1 */
table nshencap_2_1_set_nsh_flag_apply {
    actions { nshencap_set_nsh_flag; }
    default_action : nshencap_set_nsh_flag;
    size : 0;
}

/* Code from anon_5 */
action vlan_add_init_metadata() {
}

action vlan_add_do_VLAN_encap(tci) {
    add_header(vlan);
    modify_field(vlan.TCI, tci);
    modify_field(vlan.nextType, ethernet.etherType);
    modify_field(ethernet.etherType, ETHERTYPE_VLAN);
}

table vlan_add_2_2_init_metadata_apply {
    actions { vlan_add_init_metadata; }
    default_action : vlan_add_init_metadata;
    size:0;
}

table vlan_add_2_2_add_vlan {
	actions { vlan_add_do_VLAN_encap; }
    default_action : vlan_add_do_VLAN_encap;
}

/* Code from anon_6 */
table ipv4forward_2_3_ipv4_forward_table {
	reads {
		ipv4.dstAddr: lpm;
	}
	actions {
		ipv4forward_ipv4_forward_table_hit;
		ipv4forward_ipv4_forward_table_miss;
	}
	default_action : ipv4forward_ipv4_forward_table_miss;
	size : IPV4_FORWARD_TABLE_SIZE;
}

table ipv4forward_2_3_init_metadata_apply {
    actions { ipv4forward_init_metadata; }
    default_action : ipv4forward_init_metadata;
    size:0;
}

table ipv4forward_2_3_drop_pkt_apply {
    actions { ipv4forward_drop_pkt; }
    default_action : ipv4forward_drop_pkt;
    size : 0;
}

/* Code from nsh_1_1 */
table nshencap_1_1_set_nsh_flag_apply {
    actions { nshencap_set_nsh_flag; }
    default_action : nshencap_set_nsh_flag;
    size : 0;
}

/* Code from anon_2 */
action nat_drop(){
	modify_field(meta.drop_flag, 1);
}

action nat_init_metadata() {   
}

action nat_set_if_info(ipv4_addr, mac_addr, is_ext ){
	modify_field(meta.if_ipv4_addr, ipv4_addr);
	modify_field(meta.if_mac_addr, mac_addr);
	modify_field(meta.is_ext_if, is_ext);
}

action nat_nat_miss_int_to_ext() {
	modify_field(meta.nat_table_miss, 1);
    nat_drop();
}

action nat_nat_miss_ext_to_int() {
	modify_field(meta.nat_table_miss, 1);
    nat_drop();
}

action nat_nat_hit_int_to_ext(srcAddr, srcPort){
	modify_field(meta.nat_table_miss, 0);
	modify_field(meta.ipv4_sa, srcAddr);
    modify_field(meta.ipv4_da, ipv4.dstAddr);
	modify_field(meta.tcp_sp, srcPort);
    modify_field(meta.tcp_dp, tcp.dstPort);
}

action nat_nat_hit_ext_to_int(dstAddr, dstPort){
	modify_field(meta.nat_table_miss, 0);
	modify_field(meta.ipv4_sa, ipv4.srcAddr);
	modify_field(meta.ipv4_da, dstAddr);
    modify_field(meta.tcp_sp, tcp.srcPort);
	modify_field(meta.tcp_dp, dstPort);
}

action nat_do_rewrites() {
	nat_set_ip();
	nat_set_tcp();
}

action nat_set_ethernet() {
}

action nat_set_ip() {
	modify_field(ipv4.srcAddr, meta.ipv4_sa);
	modify_field(ipv4.dstAddr, meta.ipv4_da);
}

action nat_set_tcp() {
	modify_field(tcp.srcPort, meta.tcp_sp);
	modify_field(tcp.dstPort, meta.tcp_dp);
}

table nat_1_2_init_metadata_apply {
    actions { nat_init_metadata; }
    default_action : nat_init_metadata;
    size : 0;
}

table nat_1_2_interface_info_table {
	reads { ig_intr_md.ingress_port : exact; }
	actions {
		nat_set_if_info;
		nat_drop;
	}
	default_action : nat_drop();
	size : 10;
}

table nat_1_2_nat {
	reads {
		meta.is_ext_if: exact;
		ipv4: valid;
		tcp: valid;
		ipv4.srcAddr: ternary;
		ipv4.dstAddr: ternary;
		tcp.srcPort: ternary;
		tcp.dstPort: ternary;
	}
	actions {
		nat_nat_hit_int_to_ext;
		nat_nat_miss_int_to_ext;
		nat_nat_hit_ext_to_int;
		nat_nat_miss_ext_to_int;
		nat_drop;
	}
	default_action : nat_drop;
	size : NAT_TABLE_SIZE;
}

table nat_1_2_do_rewrites_apply {
	actions { nat_do_rewrites; }
	default_action : nat_do_rewrites;
	size : 0;
}

/* Code from anon_3 */
table ipv4forward_1_3_ipv4_forward_table {
	reads {
		ipv4.dstAddr: lpm;
	}
	actions {
		ipv4forward_ipv4_forward_table_hit;
		ipv4forward_ipv4_forward_table_miss;
	}
	default_action : ipv4forward_ipv4_forward_table_miss;
	size : IPV4_FORWARD_TABLE_SIZE;
}

table ipv4forward_1_3_init_metadata_apply {
    actions { ipv4forward_init_metadata; }
    default_action : ipv4forward_init_metadata;
    size:0;
}

table ipv4forward_1_3_drop_pkt_apply {
    actions { ipv4forward_drop_pkt; }
    default_action : ipv4forward_drop_pkt;
    size : 0;
}

	/* sys actions/tables */
action spi_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action spi_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 1);
	modify_field(meta.service_id, 1);
}
action spi_select_table_hit_1() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 2);
	modify_field(meta.service_id, 1);
}
action spi_select_table_hit_2() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 3);
	modify_field(meta.service_id, 1);
}
action spi_select_table_hit_3() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 4);
	modify_field(meta.service_id, 1);
}
table spi_select_table {
	reads {
		ipv4.dstAddr : ternary;
	}
	actions {
		spi_select_table_miss;
		spi_select_table_hit_0;
		spi_select_table_hit_1;
		spi_select_table_hit_2;
		spi_select_table_hit_3;
	}
	default_action : spi_select_table_miss;
	size:20;
}

action vlan_rm_4_1_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action vlan_rm_4_1_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 4);
	modify_field(meta.service_id, 2);
}
table vlan_rm_4_1_select_table {
	actions {
		vlan_rm_4_1_select_table_miss;
		vlan_rm_4_1_select_table_hit_0;
	}
	default_action : vlan_rm_4_1_select_table_hit_0;
	size:21;
}
action nshencap_4_2_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action nshencap_4_2_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 4);
	modify_field(meta.service_id, 3);
}
table nshencap_4_2_select_table {
	actions {
		nshencap_4_2_select_table_miss;
		nshencap_4_2_select_table_hit_0;
	}
	default_action : nshencap_4_2_select_table_hit_0;
	size:21;
}
action nshencap_3_1_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action nshencap_3_1_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 3);
	modify_field(meta.service_id, 2);
}
table nshencap_3_1_select_table {
	actions {
		nshencap_3_1_select_table_miss;
		nshencap_3_1_select_table_hit_0;
	}
	default_action : nshencap_3_1_select_table_hit_0;
	size:21;
}
action acl_3_2_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action acl_3_2_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 3);
	modify_field(meta.service_id, 3);
}
table acl_3_2_select_table {
	actions {
		acl_3_2_select_table_miss;
		acl_3_2_select_table_hit_0;
	}
	default_action : acl_3_2_select_table_hit_0;
	size:21;
}
action nshencap_2_1_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action nshencap_2_1_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 2);
	modify_field(meta.service_id, 2);
}
table nshencap_2_1_select_table {
	actions {
		nshencap_2_1_select_table_miss;
		nshencap_2_1_select_table_hit_0;
	}
	default_action : nshencap_2_1_select_table_hit_0;
	size:21;
}
action vlan_add_2_2_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action vlan_add_2_2_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 2);
	modify_field(meta.service_id, 3);
}
table vlan_add_2_2_select_table {
	actions {
		vlan_add_2_2_select_table_miss;
		vlan_add_2_2_select_table_hit_0;
	}
	default_action : vlan_add_2_2_select_table_hit_0;
	size:21;
}
action nshencap_1_1_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action nshencap_1_1_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 1);
	modify_field(meta.service_id, 2);
}
table nshencap_1_1_select_table {
	actions {
		nshencap_1_1_select_table_miss;
		nshencap_1_1_select_table_hit_0;
	}
	default_action : nshencap_1_1_select_table_hit_0;
	size:21;
}
action nat_1_2_select_table_miss() {
	modify_field(meta.service_path_id, 0);
	sys_set_drop_flag();
}
action nat_1_2_select_table_hit_0() {
	modify_field(meta.prev_spi, meta.service_path_id);
	modify_field(meta.prev_si, meta.service_id);
	modify_field(meta.service_path_id, 1);
	modify_field(meta.service_id, 3);
}
table nat_1_2_select_table {
	actions {
		nat_1_2_select_table_miss;
		nat_1_2_select_table_hit_0;
	}
	default_action : nat_1_2_select_table_hit_0;
	size:21;
}
action sys_init_metadata() {
	modify_field(meta.forward_flag, 0);
	modify_field(meta.controller_flag, 0);
	modify_field(meta.nsh_flag, 0);
}
table sys_init_metadata_apply {
	actions {
		sys_init_metadata;
	}
	default_action : sys_init_metadata;
	size:0;
}

control ingress {
	apply(sys_init_metadata_apply);

	if (valid(nsh)) {
		apply(sys_remove_nsh_header_apply);
	}
	else {
	apply(spi_select_table);
	}

	if (meta.service_path_id==4 and meta.service_id==1 and meta.drop_flag==0 and meta.controller_flag==0) {
	/* anon_10 */
	apply(vlan_rm_4_1_init_metadata_apply);
	if(valid(vlan)){
		apply(vlan_rm_4_1_rm_vlan);
	}
	/* End anon_10 */
	apply(vlan_rm_4_1_select_table);
	}
	else if (meta.service_path_id==4 and meta.service_id==3 and meta.drop_flag==0 and meta.controller_flag==0) {
	/* anon_12 */
	apply(ipv4forward_4_3_init_metadata_apply);
	apply(ipv4forward_4_3_ipv4_forward_table);
	/* End anon_12 */
	}
	else if (meta.service_path_id==3 and meta.service_id==2 and meta.drop_flag==0 and meta.controller_flag==0) {
	/* anon_8 */
	apply(acl_3_2_init_metadata_apply);
	apply(acl_3_2_acl_table);
	/* End anon_8 */
	/* anon_9 */
	apply(ipv4forward_3_3_init_metadata_apply);
	apply(ipv4forward_3_3_ipv4_forward_table);
	/* End anon_9 */
	}
	else if (meta.service_path_id==2 and meta.service_id==2 and meta.drop_flag==0 and meta.controller_flag==0) {
	/* anon_5 */
	apply(vlan_add_2_2_init_metadata_apply);
	apply(vlan_add_2_2_add_vlan);
	/* End anon_5 */
	/* anon_6 */
	apply(ipv4forward_2_3_init_metadata_apply);
	apply(ipv4forward_2_3_ipv4_forward_table);
	/* End anon_6 */
	}
	else if (meta.service_path_id==1 and meta.service_id==2 and meta.drop_flag==0 and meta.controller_flag==0) {
	/* anon_2 */
    apply(nat_1_2_init_metadata_apply);
	apply(nat_1_2_interface_info_table);
	apply(nat_1_2_nat);
	if (meta.nat_table_miss == 0){
		apply(nat_1_2_do_rewrites_apply);
	}
	/* End anon_2 */
	/* anon_3 */
	apply(ipv4forward_1_3_init_metadata_apply);
	apply(ipv4forward_1_3_ipv4_forward_table);
	/* End anon_3 */
	}

	if ((meta.service_path_id==4 and meta.service_id==2) or (meta.service_path_id==3 and meta.service_id==1) or (meta.service_path_id==2 and meta.service_id==1) or (meta.service_path_id==1 and meta.service_id==1)) {
		apply( nshencap_4_2_set_nsh_flag_apply );
	}

	if ( (meta.controller_flag == 1) or (meta.nsh_flag == 1) ) {
		apply(sys_valid_nsh_header_apply);
		if(valid(vlan)) {
			apply(sys_handle_next_proto_vlan_apply);
		}
		else {
			apply(sys_handle_next_proto_ipv4_apply);
		}
	}
	if (meta.nsh_flag==1) {
		apply(sys_send_to_bess_apply);
	}
	if (meta.controller_flag==1) {
		apply(sys_send_to_controller_apply);
	}
	if (meta.drop_flag==1) {
		apply(sys_drop_apply);
	}
} // end control


/************************  E G R E S S  **********************************/
control egress {
}

