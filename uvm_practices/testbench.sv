// Sequence item
class mem_seq_item extends uvm_sequence_item;
 
  //data and control fields
  rand bit [3:0] addr;
  rand bit       wr_en;
  rand bit       rd_en;
  rand bit [7:0] wdata;
       bit [7:0] rdata;
 
  //Utility and Field macros
  `uvm_object_utils_begin(mem_seq_item)
    `uvm_field_int(addr,UVM_ALL_ON)
    `uvm_field_int(wr_en,UVM_ALL_ON)
    `uvm_field_int(rd_en,UVM_ALL_ON)
    `uvm_field_int(wdata,UVM_ALL_ON)
  `uvm_object_utils_end
 
  //Constructor
  function new(string name = "mem_seq_item");
    super.new(name);
  endfunction

  // Constraint: generate any one among write and read
  constraint wr_rd_c { wr_en != rd_en; };
endclass

// Sequence
class mem_sequence extends uvm_sequence#(.REQ(mem_seq_item));
    // `uvm_declare_p_sequencer (uvm_sequencer #(my_data))
    `uvm_sequence_utils(mem_sequence, mem_sequencer);

    //Constructor
    function new(string name = "mem_sequence");
      super.new(name);
    endfunction

    virtual task pre_body();
        req = mem_seq_item::type_id::create("req");
    endtask

    // Generate and send the sequence_item in body() method
    virtual task body();
        /*
        wait_for_grant();
        req.randomize();
        send_request(req);
        wait_for_item_done();
        */
        `uvm_do(req);
    endtask
endclass

// Write sequence
class mem_wr_seq extends mem_sequence;
   
  `uvm_object_utils(mem_wr_seq)
    
  //Constructor
  function new(string name = "mem_wr_seq");
    super.new(name);
  endfunction
   
  virtual task body();
    `uvm_do_with(req, {req.wr_en == 1;});
  endtask
   
endclass 

// Read sequence
class mem_rd_seq extends mem_sequence;
  `uvm_object_utils(mem_rd_seq)
    
  //Constructor
  function new(string name = "mem_rd_seq");
    super.new(name);
  endfunction
   
  virtual task body();
    `uvm_do_with(req, {req.rd_en == 1;});
  endtask
endclass

// Sequencer
class mem_sequencer extends uvm_sequencer#(mem_seq_item);
  `uvm_component_utils(mem_sequencer)
 
  //constructor
  function new(string name, uvm_component parent) 
    super.new(name, parent);
  endfunction
endclass

// Driver
class mem_driver extends uvm_driver #(mem_seq_item);
  // Virtual Interface
  virtual mem_if vif;

  `uvm_component_utils(mem_driver)

  // Constructor
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new
 
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(virtual mem_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(req);
        drive(); 
        seq_item_port.item_done();
    end
  endtask
  
  virtual task drive();
    req.print();
      `DRIV_IF.wr_en <= 0;
      `DRIV_IF.rd_en <= 0;
      @(posedge vif.DRIVER.clk);
      `DRIV_IF.addr <= req.addr;
    if(req.wr_en) begin
        `DRIV_IF.wr_en <= req.wr_en;
        `DRIV_IF.wdata <= req.wdata;
      //$display("\tADDR = %0h \tWDATA = %0h",req.addr,trans.wdata);
        @(posedge vif.DRIVER.clk);
      end
    if(req.rd_en) begin
        `DRIV_IF.rd_en <= req.rd_en;
        @(posedge vif.DRIVER.clk);
        `DRIV_IF.rd_en <= 0;
        @(posedge vif.DRIVER.clk);
        req.rdata = `DRIV_IF.rdata;
       // $display("\tADDR = %0h \tRDATA = %0h",trans.addr,`DRIV_IF.rdata);
      end
      $display("-----------------------------------------");
  endtask : drive
endclass : mem_driver

/* 
 * Monitor
 *
 * samples the DUT signals through the virtual interface and 
 * converts the signal level activity to the transaction level.
 */

class mem_monitor extends uvm_monitor;
  // Virtual Interface
  virtual mem_if vif;

  // Step 4
  uvm_analysis_port #(mem_seq_item) item_collected_port;

  // 5. Declare seq_item handle, Used as a place holder for sampled signal activity,
  mem_seq_item trans_collected;

  `uvm_component_utils(mem_monitor)
 
  // new - constructor
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // Step 3
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual mem_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction : build_phase

  /*
  6. Add Sampling logic in run_phase,

    sample the interface signal and assign to trans_collected handle
    sampling logic is placed in the forever loop
  */

  virtual task run_phase(uvm_phase phase);
    forever begin
      //sampling logic    
      @(posedge vif.MONITOR.clk);
      wait(vif.monitor_cb.wr_en || vif.monitor_cb.rd_en);
      trans_collected.addr = vif.monitor_cb.addr;
      if(vif.monitor_cb.wr_en) begin
        trans_collected.wr_en = vif.monitor_cb.wr_en;
        trans_collected.wdata = vif.monitor_cb.wdata;
        trans_collected.rd_en = 0;
        @(posedge vif.MONITOR.clk);
      end
      if(vif.monitor_cb.rd_en) begin
        trans_collected.rd_en = vif.monitor_cb.rd_en;
        trans_collected.wr_en = 0;
        @(posedge vif.MONITOR.clk);
        @(posedge vif.MONITOR.clk);
        trans_collected.rdata = vif.monitor_cb.rdata;
      end
      // 7. After sampling, by using the write method send the sampled transaction packet to the scoreboard,
      item_collected_port.write(trans_collected);
    end 
  endtask : run_phase 
 
endclass : mem_monitor

/*
 * Agent
 *
 * An agent is a container class contains a driver, a sequencer, and a monitor.
 */

 class mem_agent extends uvm_agent;
  mem_driver    drv;
  mem_sequencer sqr;
  mem_monitor   mon;
 
  // UVM automation macros for general components
  `uvm_component_utils(mem_agent)
 
  // constructor
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (is_active() == UVM_ACTIVE) begin
      drv = mem_driver::type_id::create("drv", this);
      sqr = mem_sequencer::type_id::create("sqr", this);
      mon = mem_monitor::type_id::create("mon", this);
    end
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    if (is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction : connect_phase
endclass : mem_agent

/*
 * Scoreboard
 */

class mem_scoreboard extends uvm_scoreboard;
  // 2. Declare and Create TLM Analysis port, (to receive transaction pkt from Monitor),
  //
  // Declaring port
  uvm_analysis_imp#(mem_seq_item, mem_scoreboard) item_collected_export;
 
  `uvm_component_utils(mem_scoreboard)
 
  // new - constructor
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    item_collected_export = new("item_collected_export", this);
  endfunction: build_phase

  // write
  virtual function void write(mem_seq_item pkt);
    $display("SCB:: Pkt recived");
    pkt.print();
  endfunction : write
 
  // run phase
  virtual task run_phase(uvm_phase phase);
    --- comparision logic ---   
  endtask : run_phase
endclass : mem_scoreboard

/*
 * Environment/env
 */

class mem_model_env extends uvm_env;
  mem_agent mem_agent;
  mem_scoreboard mem_scb; 
  `uvm_component_utils(mem_model_env)
     
  // new - constructor
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    mem_agnt = mem_agent::type_id::create("mem_agnt", this);
    mem_scb  = mem_scoreboard::type_id::create("mem_scb", this);
  endfunction: build_phase
  
  // connecting monitor to scoreboard port
  function void connect_phase(uvm_phase phase)
    mem_agent.mon.item_collected_port.connect(mem_scb.item_collected_export);
  endfunction
 
endclass : mem_model_env

class mem_model_test extend uvm_test;
  `uvm_component_utils(mem_model_test)
 
  function new(string name = "mem_model_test",uvm_component parent=null);
    super.new(name,parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    mem_agnt = ::type_id::create("mem_agnt", this);
    mem_scb  = mem_scoreboard::type_id::create("mem_scb", this);
  endfunction: build_phase

  task 
  endtask 
  
  // 2. Must c env and sequence,
  mem_agent = agt;
  mem_sequence seq;
  
  //3. Create env and sequence,
  env = mem_model_env::type_id::create("env",this);
  seq = mem_sequence::type_id::create("seq");

  //4. Start sequecties
  seq.start(env.mem_agent.sequencer);
 endclass : mem_model_test

 module tbench_top;
   
  //clock and reset signal declaration
  bit clk;
  bit reset;
   
  //clock generation
  always #5 clk = ~clk;
   
  //reset Generation
  initial begin
    reset = 1;
    #5 reset =0;
  end
   
  //creatinng instance of interface, inorder to connect DUT and testcase
  mem_if intf(clk,reset);
   
  //DUT instance, interface signals are connected to the DUT ports
  memory DUT (
    .clk(intf.clk),
    .reset(intf.reset),
    .addr(intf.addr),
    .wr_en(intf.wr_en),
    .rd_en(intf.rd_en),
    .wdata(intf.wdata),
    .rdata(intf.rdata)
   );
   
  //enabling the wave dump
  initial begin
    uvm_config_db#(virtual mem_if)::set(uvm_root::get(),"*","vif",intf);
    $dumpfile("dump.vcd"); $dumpvars;
  end
   
  initial begin
    run_test();
  end
endmodule