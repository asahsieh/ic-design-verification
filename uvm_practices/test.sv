module top_tb #(
    parameters
) (
    port_list
);

// UVM start up
initial begin
    uvm_config_db #(virtual mem_if)::set(null, "*", "vif", vif)
end
endmodule