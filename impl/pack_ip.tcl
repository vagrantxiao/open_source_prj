

create_project project_2 /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/out/project_2 -part xczu3eg-sbva484-1-i
set_property board_part avnet.com:ultra96v2:part0:1.1 [current_project]
ipx::infer_core -vendor user.org -library user -taxonomy /UserIP /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/out
add_files -norecurse {/home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/hdl/datamover_m1_m_axi.sv /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/hdl/axi4_aw.sv /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/hdl/axi4_r.sv /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/hdl/axi4_w.sv /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/hdl/axi4_ar.sv}
update_compile_order -fileset sources_1
add_files -norecurse /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/hdl/skid_buffer.sv
update_compile_order -fileset sources_1
ipx::package_project -root_dir /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/out/my_ip -vendor user.org -library user -taxonomy /UserIP -import_files -set_current false
ipx::unload_core /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/out/my_ip/component.xml
ipx::edit_ip_in_project -upgrade true -name tmp_edit_project -directory /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/out/my_ip /home/ylxiao/ws221/job_hunting/F004_vcoding/C025_axix4/out/my_ip/component.xml
update_compile_order -fileset sources_1
current_project project_2
current_project tmp_edit_project
close_project
close_project

