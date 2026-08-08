// SPDX-License-Identifier: GPL-2.0
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>

static int trigger;
module_param(trigger, int, 0);

/* 第二周故障版本保留如下，trigger=1时写入NULL地址并触发oops。 */
// static int __init null_deref_init(void)
// {
//   int *ptr = NULL;

//   pr_info("null-deref loaded\n");

//   if (trigger)
//     *ptr = 1;

//   return 0;
// }

static int __init null_deref_init(void)
{
	int data = 1;
	int *ptr = &data;

	pr_info("null-deref loaded\n");

	if (trigger)
		*ptr = 1;

	return 0;
}

static void __exit null_deref_exit(void)
{
	pr_info("null-deref unloaded\n");
}

module_init(null_deref_init);
module_exit(null_deref_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("qianlizhixing");
MODULE_DESCRIPTION("null-deref demo");
MODULE_VERSION("1.0.0");
