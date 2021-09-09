/*
 * @Author: Maslow<wangfugen@126.com>
 * @Date: 2021-07-30 10:30:29
 * @LastEditTime: 2021-09-09 23:42:13
 * @Description: 
 */

import { Constants } from '../constants'
import { DatabaseAgent } from "../lib/database"
import { PolicyAgentInstance } from '../lib/policy-agent'
import { PolicyDataStruct } from '../lib/policy-agent/types'


/**
 * Get all access policies
 */
export async function getPolicyRules() {
  const db = DatabaseAgent.accessor.db
  const docs = await db.collection(Constants.policy_collection)
    .find({})
    .toArray<PolicyDataStruct>()

  return docs
}


/**
 * Applying access policies' rules
 */
export async function applyPolicyRules() {
  const policies = await getPolicyRules()
  PolicyAgentInstance.clear()
  for (const policy of policies) {
    await PolicyAgentInstance.set(policy.name, policy)
  }
}