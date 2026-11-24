-- Self-checking testbench for circuito.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_data_pkg.all;

entity circuito_tb is
  generic (
    CLK_PERIOD : time := 10 ns
    );
end circuito_tb;

architecture behavior of circuito_tb is

  component circuito is
    port (
      clk     : in  std_logic;
      reset   : in  std_logic;
      done    : out std_logic;
      we      : out std_logic;
      addr    : out std_logic_vector(3 downto 0);
      dataOUT : out std_logic_vector(31 downto 0));
  end component;

  signal clk     : std_logic := '0';
  signal reset   : std_logic := '1';
  signal done    : std_logic;
  signal we      : std_logic;
  signal addr    : std_logic_vector(3 downto 0);
  signal dataOUT : std_logic_vector(31 downto 0);

  signal sim_end : boolean := false;

  signal n_writes    : integer := 0;
  signal done_seen   : boolean := false;
  signal latency     : integer := 0;
  signal error_count : integer := 0;

  constant TIMEOUT_CYCLES : integer := 3000;

  function model return c_vec_t is
    variable c   : c_vec_t;
    variable acc : integer;
  begin
    for m in 0 to 15 loop
      acc := 0;
      for k in 0 to 63 loop
        acc := acc + A_MAT(m)(k) * B_VEC(k);
      end loop;
      if acc > 0 then
        c(m) := acc;
      else
        c(m) := 0;
      end if;
    end loop;
    return c;
  end function;

  constant C_REF : c_vec_t := model;

  function hex(v : std_logic_vector) return string is
    constant digits : string(1 to 16) := "0123456789ABCDEF";
    variable s : string(1 to v'length / 4);
    variable n : integer;
  begin
    for i in s'range loop
      if is_x(v(v'left - 4 * (i - 1) downto v'left - 4 * i + 1)) then
        s(i) := 'X';
      else
        n := to_integer(unsigned(v(v'left - 4 * (i - 1) downto v'left - 4 * i + 1)));
        s(i) := digits(n + 1);
      end if;
    end loop;
    return s;
  end function;

begin

  uut : circuito
    port map (clk => clk, reset => reset, done => done,
              we => we, addr => addr, dataOUT => dataOUT);

  clk_process : process
  begin
    while not sim_end loop
      clk <= '0';
      wait for CLK_PERIOD / 2;
      clk <= '1';
      wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  -- Checks the outputs once per cycle, at the falling edge.
  -- In the post-implementation simulation the outputs reach the pins about one
  -- clock period after the rising edge, and some bits arrive earlier than others.
  -- Sampling at the rising edge then mixes bits from two cycles. Half a period
  -- away from the edge, every bit is stable (behavioral: delay 0, timing: ~10 ns).
  monitor : process (clk)
    variable rst_prev : std_logic := '1';
    variable cycles   : integer   := 0;
    variable m        : integer;
    variable pending  : boolean   := false;  -- a write happened in the last cycle
    variable pend_m   : integer   := 0;
  begin
    if falling_edge(clk) then
      if reset = '1' then
        if rst_prev = '1' then
          -- only a real '1' is an error: right after power-up the delayed
          -- outputs of the timing simulation can still be 'U'/'X'
          assert we /= '1' report "we = 1 while reset is high" severity error;
          assert done /= '1' report "done = 1 while reset is high" severity error;
          if we = '1' or done = '1' then
            error_count <= error_count + 1;
          end if;
        end if;
        cycles    := 0;
        pending   := false;
        n_writes  <= 0;
        done_seen <= false;
      else
        cycles := cycles + 1;

        -- dataOUT is OMemC's read port: C[m] appears one cycle after its write.
        if pending then
          if dataOUT /= std_logic_vector(to_unsigned(C_REF(pend_m), 32)) then
            report "C[" & integer'image(pend_m) & "] = 0x" & hex(dataOUT)
              & ", expected " & integer'image(C_REF(pend_m)) severity error;
            error_count <= error_count + 1;
          end if;
          pending := false;
        end if;

        if we = '1' then
          m := n_writes;
          if done_seen or done = '1' then
            report "write after done (addr " & hex(addr) & ")" severity error;
            error_count <= error_count + 1;
          elsif m > 15 then
            report "more than 16 writes" severity error;
            error_count <= error_count + 1;
          else
            if addr /= std_logic_vector(to_unsigned(m, 4)) then
              report "write #" & integer'image(m) & " went to address 0x" & hex(addr)
                & ", expected " & integer'image(m) severity error;
              error_count <= error_count + 1;
            end if;
            pending := true;
            pend_m  := m;
          end if;
          n_writes <= n_writes + 1;
        end if;

        if done = '1' and not done_seen then
          done_seen <= true;
          latency   <= cycles - 1;
          if n_writes /= 16 then
            report "done went high after " & integer'image(n_writes)
              & " writes, expected 16" severity error;
            error_count <= error_count + 1;
          end if;
        elsif done_seen and done /= '1' then
          report "done went low again without a reset" severity error;
          error_count <= error_count + 1;
        end if;
      end if;
      rst_prev := reset;
    end if;
  end process;

  stimulus : process

    procedure release_reset is
    begin
      wait until falling_edge(clk);
      reset <= '0';
    end procedure;

    procedure apply_reset(cycles : integer) is
    begin
      wait until falling_edge(clk);
      reset <= '1';
      for i in 1 to cycles loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    variable runs_ok  : integer := 0;
    variable mac_rate : real;

    procedure full_run(name : string) is
      variable waited : integer := 0;
    begin
      release_reset;
      while not done_seen and waited < TIMEOUT_CYCLES loop
        wait until rising_edge(clk);
        waited := waited + 1;
      end loop;
      wait until falling_edge(clk);
      if not done_seen then
        report name & ": timeout, done never went high" severity failure;
      end if;
      for i in 1 to 20 loop
        wait until rising_edge(clk);
      end loop;
      wait until falling_edge(clk);
      assert n_writes = 16
        report name & ": " & integer'image(n_writes) & " writes, expected 16" severity error;
      if n_writes = 16 and error_count = 0 then
        runs_ok := runs_ok + 1;
      end if;
      report name & ": done = 1 after " & integer'image(latency) & " clock cycles";
    end procedure;

  begin
    for m in 0 to 15 loop
      assert C_REF(m) = C_EXP(m)
        report "reference mismatch: VHDL model C[" & integer'image(m) & "] = "
        & integer'image(C_REF(m)) & ", memgen.py = " & integer'image(C_EXP(m))
        severity failure;
    end loop;
    report "memory set " & SET_NAME & ": reference model OK";

    -- run 1
    reset <= '1';
    for i in 1 to 20 loop
      wait until rising_edge(clk);
    end loop;
    full_run("run 1");

    -- run 2: reset in the middle of a run
    apply_reset(3);
    release_reset;
    for i in 1 to 300 loop
      wait until rising_edge(clk);
    end loop;
    assert n_writes > 0 and not done_seen
      report "mid-run reset test: expected to be in the middle of a run" severity error;
    apply_reset(3);
    full_run("run 2 (after mid-run reset)");

    mac_rate := 1024.0 / (real(latency) * real(CLK_PERIOD / 1 ps) * 1.0e-12);
    if runs_ok = 2 and error_count = 0 then
      report "circuito_tb passed: set " & SET_NAME & ", latency "
        & integer'image(latency) & " cycles = "
        & integer'image(latency * (CLK_PERIOD / 1 ps) / 1000) & " ns at "
        & integer'image(CLK_PERIOD / 1 ps) & " ps clock, "
        & integer'image(integer(mac_rate / 1.0e6)) & " MMAC/s";
    else
      report "circuito_tb FAILED: set " & SET_NAME & ", " & integer'image(error_count)
        & " errors" severity failure;
    end if;
    sim_end <= true;
    wait;
  end process;

end behavior;
