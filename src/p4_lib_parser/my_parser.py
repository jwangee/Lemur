"""
* The script implements the abstract parser class. The class can parse
* the P4 header parser specification part (my_parser) in a target P4
* module.
"""

import copy
import header
import collections

TYPE_IPv4 = "0x0800";
TYPE_IPv6 = "0x86DD";
TYPE_TCP = "0x06";
TYPE_UDP = "0x11";

def convert_str_to_dict(input_dict_str):
    """ This function parses a dict (in a str format) to a real Python
    dict.
    Args: input_dict_str (the input dict in string)
    Return: result_dict
    """
    result_dict = collections.OrderedDict()
    element_key = None
    element_value = None

    s_index = input_dict_str.index('{')
    e_index = input_dict_str.index('}')
    dict_content = input_dict_str[ (s_index+1):e_index]
    dict_elements = dict_content.split(',')
    for element in dict_elements:
        if ':' not in element:
            continue

        mark_index = element.index( ':' )
        element_key = (element[:mark_index]).strip()
        element_value = (element[(mark_index+1):]).strip()
        result_dict[element_key] = element_value
    return result_dict

def convert_str_to_args(input_args_str):
    """ This function is used to parse a string which is a function call
    It returns a list of args, which starts with the function name.
    (i.e. res_args[0] = "function name")
    """
    result_args = []
    args = []
    s_index = input_args_str.index('(')
    e_index = input_args_str.index(')')
    function_name = (input_args_str[:s_index]).strip()
    result_args.append(function_name)

    args_content = input_args_str[ s_index+1:e_index ]
    args_length = len(args_content)
    dict_flag = False
    s_index = 0
    e_index = -1
    for i in range(args_length):
        if args_content[i] == '{':
            dict_flag = True
        elif args_content[i] == '}':
            dict_flag = False
        elif args_content[i] == ',':
            if not dict_flag:
                e_index = i
                args.append( args_content[s_index:e_index].strip())
                s_index = i+1
            else:
                continue
        else:
            continue
    args.append( args_content[s_index:args_length].strip() )

    for arg in args:
        result_args.append(arg.strip())
    return result_args


class parse_state(object):
    def __init__(self, state_name="",state_field=None,state_branches=0, \
        state_transition_info=None):

        self.name = state_name
        self.branch_num = state_branches
        self.transition_field = None
        self.transition_info = collections.OrderedDict()

        if state_field != None:
            self.transition_field = copy.deepcopy(state_field)
        if state_transition_info != None:
            self.transition_info = copy.deepcopy(state_transition_info)
        return

    def generate_p4_code(self, header_defined_state=True):
        res = ""
        res += "state parse_%s {\n" %( self.name.lower() )

        if header_defined_state:
            res += "\tpacket.extract(hdr.%s);\n" %( self.name.lower() )

        if self.transition_field != "None":
            res += "\ttransition select(hdr.%s.%s) {\n" %(self.name.lower(), self.transition_field)

        branch_list = self.transition_info.items()
        for i in range( self.branch_num ):
            res += "\t%s: parse_%s;\n" %( branch_list[i][0], branch_list[i][1].lower() )

        if self.branch_num > 0:
            res += "\tdefault: accept;\n"
            res += "\t}\n"
        else:
            # There is no branch for this parser_state
            # It means we should directly accept this packet and do nothing
            res += "\ttransition accept;\n"
        res += "}\n"
        return res

    def generate_p414_code(self, header_defined_state=True):
        res = ""
        res += 'parser parse_%s {\n' %(self.name.lower())
        if header_defined_state:
            res += '\textract(%s);\n' %(self.name.lower())

        if self.transition_field != 'None':
            res += '\treturn select(latest.%s) {\n' %(self.transition_field)
        
        branch_list = self.transition_info.items()
        for i in range(self.branch_num):
            res += '\t\t%s : parse_%s;\n' %(branch_list[i][0], branch_list[i][1].lower())
        if self.branch_num > 0:
            res += '\t\tdefault: ingress;\n'
            res += '\t}\n'
        else:
            res += "\treturn ingress;\n"
        res += '}\n'
        return res

    def is_same_state(self, other_state):
        return (self.name == other_state.name)

    def merge_state(self, other_state):
        res_count = 0
        if self.transition_field == "None" and other_state.transition_field != "None":
            self.transition_field = copy.deepcopy(other_state.transition_field)

        for i in range( other_state.branch_num ):
            # merge every branch into the self state
            for key, val in other_state.transition_info.items():
                if key not in self.transition_info:
                    self.transition_info[key] = val
                    self.branch_num += 1        
        return

    def print_parser_state(self):
        """ This function outputs the current parser state in a human-readable format.
        """
        print "State name: %s" %(self.name)

    def __cmp__(self, other):
        if self.name == other.name:
            return 0
        elif self.name < other.name:
            return -1
        else:
            return 1

class myparser:
    def __init__(self, input_header_list=None, input_state_list=None):
        self.all_headers = []
        self.state_list = []
        if input_header_list != None:
            self.all_headers = copy.deepcopy(input_header_list)
        if input_state_list != None:
            self.state_list = copy.deepcopy(input_state_list)
        self.p4_code = ""
        return

    def read_transition_rules(self, input_filename):
        hp = header.header_parser()
        hp.read_headers( input_filename )
        self.all_headers = hp.headers

        with open(input_filename, 'r') as fp:
            line_count = 0
            for line in fp:
                line_count += 1
                line=line.strip()
                if line == '':
                    continue
                if line[:4] == "set ":
                    args = convert_str_to_args(line[4:])
                    new_parse_state = parse_state(args[0], args[1], int(args[2]), \
                        convert_str_to_dict( args[3] ))
                    self.state_list.append(new_parse_state)
        return

    def generate_p4_code(self):
        res = ""
        res += "/*************************************************************************\n"
        res += "************************  P A R S E R  **********************************\n"
        res += "*************************************************************************/\n\n"
        res += "parser MyParser(packet_in packet,\n\tout headers hdr,\n\tinout metadata meta,\n\tinout standard_metadata_t standard_metadata){\n\n"
        res += "state start {\n"
        res += "\ttransition parse_ethernet;\n"
        res += "}\n\n"

        for pd in self.state_list:
            if pd.name in self.all_headers:
                res += pd.generate_p4_code(True)
                res += "\n"
            else:
                res += pd.generate_p4_code(False)
                res += "\n"
        res += "}\n"

        self.p4_code = res
        return

    def generate_p414_code(self):
        res = ""
        res += "/*************************************************************************\n"
        res += "************************  P A R S E R  **********************************\n"
        res += "*************************************************************************/\n\n"
        res += "parser start {\n"
        res += "\t// start with ethernet parsing\n"
        res += "\treturn parse_ethernet;\n"
        res += "}\n\n"

        for pd in self.state_list:
            if pd.name in self.all_headers:
                res += pd.generate_p414_code(True)
                res += "\n"
            else:
                res += pd.generate_p414_code(False)
                res += "\n"

        self.p4_code = res
        return

    def generate_default_code(self):
        res = ""
        return


def myparser_tester():
    input_filename = raw_input("Please input filename: ")

    mpp = myparser()
    mpp.read_transition_rules(input_filename)   
    for state in mpp.state_list:
        print state.name, state.branch_num, state.transition_info

    mpp.generate_p4_code()
    print mpp.p4_code

    mpp.generate_p414_code()
    print mpp.p4_code

if __name__ == '__main__':
    myparser_tester()
