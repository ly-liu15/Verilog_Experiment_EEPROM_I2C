module eeprom_wr(sda,scl,ack,reset,clk,wr,rd,addr,data,main_state,sh8out_buf,head_state,ff);
input 	reset,clk,wr,rd;
input[10:0]	addr;

inout 	sda;
inout[7:0]	data;

output 	scl,ack;
output ff;

output[10:0]main_state;
output[7:0]	sh8out_buf;
output[2:0]	head_state;

reg ff;
reg  scl,ack,wf,rf;
reg[1:0] head_buf,stop_buf;
reg[7:0] sh8out_buf;
reg[8:0] sh8out_state;
reg[9:0] sh8in_state;
reg[2:0] head_state,stop_state;
reg[10:0] main_state;
reg[7:0] data_from_rm;

reg link_sda,link_read,link_head,link_write,link_stop;//选通
wire sda1,sda2,sda3,sda4;

assign sda1=(link_head)?head_buf[1]:1'b0;
assign sda2=(link_write)?sh8out_buf[7]:1'b0;
assign sda3=(link_stop)?stop_buf[1]:1'b0;
assign sda4=(sda1 | sda2 | sda3);
assign sda=(link_sda)?sda4:1'bz;//
assign data=(link_read)?data_from_rm:8'hzz;

parameter 
idle=11'b00000000001,
ready=11'b00000000010,
write_start = 11'b00000000100,
ctrl_write  = 11'b00000001000,
addr_write = 11'b00000010000,
data_write = 11'b00000100000,
read_start  = 11'b00001000000,
ctrl_read   = 11'b00010000000,
data_read  = 11'b00100000000,
stop= 11'b01000000000,
ackn= 11'b10000000000,
sh8out_bit7=9'b000000001,
sh8out_bit6=9'b000000010,
sh8out_bit5=9'b000000100,
sh8out_bit4=9'b000001000,
sh8out_bit3=9'b000010000,
sh8out_bit2=9'b000100000,
sh8out_bit1=9'b001000000,
sh8out_bit0=9'b010000000,
sh8out_end= 9'b100000000;

parameter 
sh8in_begin=10'b0000000001,
sh8in_bit7 =10'b0000000010,
sh8in_bit6 =10'b0000000100,
sh8in_bit5 =10'b0000001000,
sh8in_bit4 =10'b0000010000,
sh8in_bit3 =10'b0000100000,
sh8in_bit2 =10'b0001000000,
sh8in_bit1 =10'b0010000000,
sh8in_bit0 =10'b0100000000,
sh8in_end  =10'b1000000000;

parameter   head_begin=3'b001, 
			head_bit  =3'b010,
			head_end  =3'b100, 
			stop_begin=3'b001,
			stop_bit  =3'b010, 
			stop_end  =3'b100, 
			yes=1,
			no=0;

always @(negedge clk)
if(reset)
   scl<=0;
else
   scl<=~scl;//

always @(posedge clk)
if(reset)
  begin
    link_read<=no;
	link_write<=no;
    link_head<=no;
	link_stop<=no;
    link_sda<=no;
	ack<=0;
	rf<=0;
	wf<=0;
	ff=0;
    main_state<=idle;
  end
else 
begin
   casex(main_state)
    idle:begin 
            link_read<=no;
			link_write<=no;
            link_head<=no;
			link_stop<=no;
            link_sda<=no;
            if(wr)         //wr=1, 接到写操作
               begin 
                  wf<=1;// 设置write_flag
                  main_state<=ready;
               end
            else if(rd)   //rd=1,接到读操作
               begin
                  rf<=1; //设置read_flag
                  main_state<=ready;
               end
            else
                begin
                  wf<=0;rf<=0;
                  main_state<=idle;
               end
          end      
          ready:begin 
            link_read<=no;
			link_write<=no;
            link_head<=no;
			link_stop<=yes;
            link_sda<=yes; 
            head_buf<=2;
			stop_buf<=1;
            head_state<=head_begin;//子状态机head_state
            ff<=0;
			ack<=0;
			main_state<=write_start;
           end
write_start:
           if(ff==0)
             shift_head; //task
          else     //ff=1
             begin
               sh8out_buf[7:0]<={4'b1010,addr[10:8],1'b0};
               link_head<=no;
			   link_write<=yes;
               ff<=0;
			   sh8out_state<=sh8out_bit6;
               main_state<=ctrl_write;
             end
   ctrl_write:
           if(ff==0)
             shift8_out;//task
           else     
           begin
               sh8out_state<=sh8out_bit7;
               sh8out_buf[7:0]<=addr[7:0];
               ff<=0;main_state<=addr_write;
             end
addr_write:
           if(ff==0)
              shift8_out; //task
           else
              begin
                ff<=0;
                if(wf)
                  begin
                    sh8out_state<=sh8out_bit7;
                    sh8out_buf[7:0]<=data;
                    main_state<=data_write;
                  end
                if(rf)
                  begin
                    head_buf<=2'b10;head_state<=head_begin;
                    main_state<=read_start;
                  end
              end    
              data_write:
          if(ff==0)
              shift8_out; //task
           else
              begin
                stop_state<=stop_begin;
                main_state<=stop;
                link_write<=no;ff<=0;
              end
read_start:
          if(ff==0)
              shift_head; //task
           else
              begin
                sh8out_buf<={4'b1010,addr[10:8],1'b1};
                link_head<=no;link_sda<=yes;
                link_write<=yes;ff<=0;sh8out_state<=sh8out_bit6;
                main_state<=ctrl_read;
           end
   ctrl_read:
           if(ff==0)
              shift8_out; //task
           else 
           begin
                link_sda<=no;link_write<=no;ff<=0;
                sh8in_state<=sh8in_begin;
                main_state<=data_read;
              end
data_read:
          if(ff==0)
             shift8in; //task
          else
             begin
               link_stop<=yes;link_sda<=yes;stop_state<=stop_bit;
               ff<=0;main_state<=stop;
             end
   stop:  
            if(ff==0)
              shift_stop; //task
            else
              begin
                ack<=1;ff<=0;main_state<=ackn;
              end
   ackn:   begin
             ack<=0;wf<=0;rf<=0;main_state<=idle;
           end   
default :main_state<=idle;
  endcase
end
//---------------------------------------------------------------------------------
task shift8in;//define task
  begin
   case(sh8in_state)
    sh8in_begin:sh8in_state<=sh8in_bit7;
    sh8in_bit7:
       if(scl)
         begin data_from_rm[7]<=sda;sh8in_state<=sh8in_bit6;end
       else
         sh8in_state<=sh8in_bit7;
    sh8in_bit6:
       if(scl)
         begin data_from_rm[6]<=sda;sh8in_state<=sh8in_bit5;end
       else
         sh8in_state<=sh8in_bit6;
    sh8in_bit5:
       if(scl)
         begin data_from_rm[5]<=sda;sh8in_state<=sh8in_bit4;end
       else
         sh8in_state<=sh8in_bit5;    
	sh8in_bit4:
       if(scl)
         begin data_from_rm[4]<=sda;sh8in_state<=sh8in_bit3;end
       else
         sh8in_state<=sh8in_bit4;
sh8in_bit3:
       if(scl)
         begin data_from_rm[3]<=sda;sh8in_state<=sh8in_bit2;end
       else
         sh8in_state<=sh8in_bit3;
    sh8in_bit2:
       if(scl)
         begin data_from_rm[2]<=sda;sh8in_state<=sh8in_bit1;end
       else
         sh8in_state<=sh8in_bit2;
    sh8in_bit1:
       if(scl)
         begin data_from_rm[1]<=sda;sh8in_state<=sh8in_bit0;end
       else
         sh8in_state<=sh8in_bit1;  
         sh8in_bit0:
       if(scl)
         begin data_from_rm[0]<=sda;sh8in_state<=sh8in_end;end
       else
         sh8in_state<=sh8in_bit0;
sh8in_end:
       if(scl)
         begin link_read<=yes;ff=1;sh8in_state<=sh8in_bit7;end
       else
         sh8in_state<=sh8in_end;
   default:begin
             link_read<=no;sh8in_state<=sh8in_bit7;
           end
  endcase
end
endtask

task shift8_out; //define task
begin
casex(sh8out_state)
sh8out_bit7:
   if(!scl)
   begin
       link_sda<=yes;link_write<=yes;
       sh8out_state<=sh8out_bit6;
     end
   else
     sh8out_state<=sh8out_bit7;
sh8out_bit6:
   if(!scl)
     begin
       link_sda<=yes;link_write<=yes;
       sh8out_state<=sh8out_bit5;sh8out_buf<=sh8out_buf<<1;
     end
   else
     sh8out_state<=sh8out_bit6;
     sh8out_bit5:
   if(!scl)
     begin
      sh8out_state<=sh8out_bit4;sh8out_buf<=sh8out_buf<<1;
     end
   else
     sh8out_state<=sh8out_bit5;
sh8out_bit4:
   if(!scl)
     begin
      sh8out_state<=sh8out_bit3;sh8out_buf<=sh8out_buf<<1;
     end
   else
     sh8out_state<=sh8out_bit4;
sh8out_bit3:
   if(!scl)
     begin
       sh8out_state<=sh8out_bit2;sh8out_buf<=sh8out_buf<<1;
     end
   else
     sh8out_state<=sh8out_bit3;
     sh8out_bit2:
   if(!scl)
     begin
      sh8out_state<=sh8out_bit1;sh8out_buf<=sh8out_buf<<1;
     end
   else
     sh8out_state<=sh8out_bit2;
sh8out_bit1:
   if(!scl)
     begin
       sh8out_state<=sh8out_bit0;sh8out_buf<=sh8out_buf<<1;
     end
   else
     sh8out_state<=sh8out_bit1;
sh8out_bit0:
   if(!scl)
     begin
       sh8out_state<=sh8out_end;sh8out_buf<=sh8out_buf<<1;
     end
   else
     sh8out_state<=sh8out_bit0;
     sh8out_end:
   if(!scl)
     begin
       link_sda<=no;link_write<=no;ff<=1;
     end
   else
     sh8out_state<=sh8out_end;
endcase
end
endtask
task shift_head; //define task
begin
casex(head_state)
head_begin:
   if(!scl)
     begin
        link_write<=no;link_sda<=yes;
        link_head<=yes;head_state<=head_bit;
     end
   else
     head_state<=head_begin;
     head_bit:
    if(scl)
      begin
        ff<=1;head_buf<=head_buf<<1;
        head_state<=head_end;
      end
    else
      head_state<=head_bit;
head_end:
    if(!scl)
     begin
       link_head<=no;link_write<=yes;
     end
    else
      head_state<=head_end;
endcase
end
endtask

task shift_stop; //define task
begin
casex(stop_state)
stop_begin:
   if(!scl)
     begin
       link_sda<=yes;link_write<=no;link_stop<=yes;stop_state<=stop_bit;
     end
   else
     stop_state<=stop_begin;
stop_bit:
   if(scl)
     begin
       stop_buf<=stop_buf<<1;
       stop_state<=stop_end;
     end
   else
     stop_state<=stop_bit;
     stop_end:
   if(!scl)
     begin
       link_head<=no;link_stop<=no;link_sda<=no;ff<=1;
     end
   else
     stop_state<=stop_end;
endcase
end
endtask

endmodule
